# dash-ratchet

A diff-scoped CI gate for unicode dashes. On every pull request:

1. **No unicode dash on a line the PR adds.** The failure names the file and the
   line. It never swaps the character for you, because a dash usually marks a
   sentence that wants a colon, a comma pair, or a split.
2. **The repo-wide dash total did not rise.** This one lands on the run summary,
   so the checks page shows the count without anyone expanding a job log.

A ratchet, not a sweep: a repo with hundreds of existing dashes can adopt it
immediately and pay the debt down as it touches files. The total only has to
fall, never to reach zero.

## Banned set

U+2010 through U+2015 (hyphen, non-breaking hyphen, figure dash, en dash,
em dash, horizontal bar), U+2212 (minus sign), and `&mdash;` / `&ndash;` /
`&minus;`. Each folds to a plain ASCII hyphen. A line that must keep its
character carries the marker `dash-ok` anywhere on the line. <!-- dash-ok -->

## Usage

One file in the consuming repo. The runner tier, the checkout, and the timeout
live here and update with this repo, not per consumer.

```yaml
# .github/workflows/dash-ratchet.yml
name: Dash ratchet

concurrency:
  group: dashes-pr-${{ github.event.pull_request.number }}
  cancel-in-progress: true

on:
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  dashes:
    uses: notambourine/dash-ratchet/.github/workflows/ratchet.yml@4ad5d35314782517511b8e5fc3b98d097499dc7c # v0.1.0
    with:
      exclude: |
        lib/db/migrations
```

The pinned commit is the one the `v0.1.0` tag points at.

### Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `exclude` | empty | Directories held out of the rule, one per line. For bytes that are not yours to edit: captured wire fixtures, append-only migration history. |
| `marker` | `dash-ok` | A line that carries this marker keeps its dash. |
| `base-ref` | empty | Composite action only. Override the base branch, without the `origin/` prefix; empty resolves it from the event. |

### Composite action

For a repo that needs its own runner, extra steps, or GitHub Enterprise Server.
`fetch-depth: 2` is the floor, since the gate diffs against the merge ref's
first parent. Set `base-ref` only when the checkout is not the PR merge ref,
and then fetch that branch yourself.

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  with:
    fetch-depth: 2
    persist-credentials: false
- uses: notambourine/dash-ratchet@4ad5d35314782517511b8e5fc3b98d097499dc7c # v0.1.0
```

## Local run

```bash
scripts/check-dashes.sh origin/main   # any repo with a fetched base
test/run.sh                           # behavior suite, both locales
```

Replacing a vendored copy of these scripts: delete them, call the reusable
workflow above, and move any `DASH_EXCLUDE_DIRS` entries into `exclude`.

## License

MIT
