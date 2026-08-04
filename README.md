# dash-ratchet

A diff-scoped CI gate for unicode dashes. On every pull request it makes two
assertions against the base branch:

1. **No unicode dash on a line the PR adds.** This is the assertion a
   contributor reads and fixes, because it names the file and line.
2. **The repo-wide dash total did not rise.** This is the backstop for edits
   the diff cannot see, and it is the number that has to keep falling.

The gate is a ratchet, not a sweep. A repo with hundreds of existing dashes
installs it today and pays the debt down as it touches files. The total only
has to fall; it never has to reach zero.

## Banned set

U+2010 through U+2015 (hyphen, non-breaking hyphen, figure dash, en dash,
em dash, horizontal bar), U+2212 (minus sign), and the HTML entities
`&mdash;`, `&ndash;`, `&minus;`. Each folds to a plain ASCII hyphen. <!-- dash-ok -->

A line that must keep its character (a verbatim quote, a real minus sign)
carries the marker `dash-ok` anywhere on the line, and the gate skips it.

## Usage

### Default: reusable workflow

One file in the consuming repo. The runner tier, the checkout, and the
timeout live here and update with this repo, not per consumer.

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

The pinned commit is the one the `v0.1.0` tag points at. The job runs on
`ubuntu-slim`. The `exclude` input is optional; see the inputs table.

### Escape hatch: composite action

For a repo that needs its own runner, extra steps, or GitHub Enterprise
Server (where the reusable workflow's self-checkout context is unavailable).
The checkout MUST use `fetch-depth: 0`: the gate diffs against
`origin/<base>` and counts dashes on that side too.

```yaml
jobs:
  dashes:
    runs-on: ubuntu-slim
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: notambourine/dash-ratchet@4ad5d35314782517511b8e5fc3b98d097499dc7c # v0.1.0
```

### Inputs

Both entry points take the same inputs.

| Input      | Default                    | Meaning                                          |
| ---------- | -------------------------- | ------------------------------------------------ |
| `base-ref` | `${{ github.base_ref }}`   | Base branch to diff against, no `origin/` prefix. Composite action only; the reusable workflow always uses the PR base. |
| `exclude`  | empty                      | Directories held out of the rule, one per line. For bytes that are not yours to edit: captured wire fixtures, append-only migration history. |
| `marker`   | `dash-ok`                  | A line that carries this marker keeps its dash.  |

### Local run

From a checkout of this repo, against any repo with a fetched base:

```bash
scripts/check-dashes.sh origin/main
```

`test/run.sh` runs the behavior suite: seven cases, each under the ambient
locale and again under `LC_ALL=C`.

## Design notes

- **Locale-proof.** The `git grep` pattern opens with the PCRE2 `(*UTF)`
  verb. git enables UTF mode only under a UTF-8 locale, and a container
  runner such as `ubuntu-slim` sets none; without the verb the `\x{2010}`
  escape overflows 8-bit mode and git exits 128. The perl side matches raw
  UTF-8 bytes, so invalid encoding in a file can never abort a pass.
- **Why a ratchet.** A zero-tolerance grep only ever passes at a count of
  zero, so a repo with a backlog can never adopt it. The ratchet gates the
  diff and lets the backlog decay.
- **Why no auto-fix.** A dash usually marks a sentence that wants different
  punctuation: a colon, a comma pair, a parenthesis, a split. A gate that
  names the line lets a human make that call; a blind character swap makes
  it for them.
- **One engine.** The character set, the marker, and the exclude handling
  live in `scripts/lib/dash-set.sh`, read by `scripts/check-dashes.sh`.
  Consumers reference this repo instead of vendoring the scripts, so a fix
  such as the `(*UTF)` verb lands everywhere on the next pin bump.

## Migrating from a vendored copy

If a repo carries its own `scripts/check-dashes.sh` and
`scripts/lib/dash-set.sh` from an earlier scaffold of this gate:

1. Delete both scripts (and `scripts/lib/` if now empty).
2. Replace the body of `.github/workflows/dash-ratchet.yml` with the
   reusable-workflow call above, keeping the repo's own `branches:` list.
3. Move any `DASH_EXCLUDE_DIRS` entries into the `exclude` input.

## License

MIT
