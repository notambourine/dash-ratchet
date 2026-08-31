# dash-ratchet

A diff-scoped CI gate for unicode dashes. Each pull request must add no line
carrying one, and the repo-wide total may only fall. A failure names the file
and the line; the total lands on the run summary. The gate never swaps the
character for you, because a dash usually marks a sentence that wants a colon,
a comma pair, or a split.

A ratchet, not a sweep: a repo with hundreds of existing dashes adopts it
immediately and pays the debt down as it touches files. Nothing has to reach
zero.

## Banned set

U+2010 through U+2015 (hyphen, non-breaking hyphen, figure dash, en dash,
em dash, horizontal bar), U+2212 (minus sign), and the HTML entities named
`mdash`, `ndash`, and `minus`. Each folds to a plain ASCII hyphen.

There is no per-line opt-out. Writing the old marker (`dash-` followed by `ok`)
on an added line is itself a failure, because a marker that suppresses nothing
still reads as permission to the next author. The gate cannot spell it in its
own source either. A path whose bytes are not yours to edit goes in `exclude`.

## Held out by default

A package manager's, an agent's, or an upstream author's bytes: nothing a
consumer reads and nothing anyone retypes by hand. A lockfile carrying an em
dash in an upstream deprecation notice is the case that drove the list.

```
**/node_modules/**   **/*.lock              **/CHANGELOG.md
**/vendor/**         **/package-lock.json   **/LICENSE*
**/.claude/**        **/npm-shrinkwrap.json **/CLAUDE.md
**/.cursor/**        **/pnpm-lock.yaml      **/AGENTS.md
                     **/bun.lockb
                     **/go.sum
```

`exclude-defaults: false` drops the whole list and gates those paths like any
other, which is what this repo does to itself. `exclude` adds to the list; it
never replaces it.

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
    uses: notambourine/dash-ratchet/.github/workflows/ratchet.yml@ac19421270755a042257789a577d5aa423b46b82 # v0.3.0
    with:
      exclude: |
        lib/db/migrations
```

The pinned commit is the one the `v0.3.0` tag points at.

### Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `exclude` | empty | Paths held out of the rule on top of the built-in list, one git pathspec per line. Globs work, so `*.json` and `test/fixtures/*.csv` are both valid. For bytes that are not yours to edit: captured wire fixtures, append-only migration history. |
| `exclude-defaults` | `true` | Apply the built-in hold-out list above. `false` gates those paths too. |
| `force-zero` | `false` | Require zero dashes in the checkout instead of ratcheting a count down. See below. |
| `base-ref` | empty | Composite action only. Override the base branch, without the `origin/` prefix; empty resolves it from the event. |

### Force zero

A repo already at zero has nothing to ratchet, so `force-zero: true` swaps the
three assertions for one: this tree carries no dash and no marker.

```yaml
    with:
      force-zero: true
```

One grep over one tree. No base ref, no diff, no second count, so the checkout
drops to `fetch-depth: 1` (the reusable workflow does that for you) and a dash
nobody's PR touched still fails. Take it once the ratchet reads 0 and the number
has stopped being interesting.

### Composite action

For a repo that needs its own runner, extra steps, or GitHub Enterprise Server.
`fetch-depth: 2` is the floor, since the gate diffs against the merge ref's
first parent, and `1` is enough under `force-zero`. Set `base-ref` only when the
checkout is not the PR merge ref, and then fetch that branch yourself.

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  with:
    fetch-depth: 2
    persist-credentials: false
- uses: notambourine/dash-ratchet@ac19421270755a042257789a577d5aa423b46b82 # v0.3.0
```

## Local run

```bash
scripts/check-dashes.sh origin/main   # any repo with a fetched base
scripts/check-dashes.sh --staged      # HEAD against the index, no ref needed
scripts/check-dashes.sh --force-zero  # whole tree must carry none, no base ref
test/run.sh                           # behavior suite, both locales
```

## Pre-commit hook

`--staged` runs the same three assertions against the index instead of a ref, so
it needs no base branch and no network. Point a hook at a checkout of this repo:

```bash
# .git/hooks/pre-commit
exec /path/to/dash-ratchet/scripts/check-dashes.sh --staged
```

Local only. `--no-verify` skips it, a fresh clone never had it, and no other
contributor is running it, so the workflow stays the gate. The hook only makes
the feedback arrive sooner for whoever installed it.

## License

MIT
