# dash-ratchet

Reject added lines containing Unicode dashes and increases in the repository
total. Existing dashes can stay until edited. Failures report file and line;
counts appear in the run summary. No automatic fixes.

## Usage

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
    uses: notambourine/dash-ratchet/.github/workflows/ratchet.yml@556a4457c467fb9c28a3240f7f030bf9204cb357 # v0.4.0
    with:
      exclude: |
        lib/db/migrations
```

The pinned commit is the one the `v0.4.0` tag points at.

| Input | Default | Effect |
| --- | --- | --- |
| `exclude` | empty | Additional exclusions, one git pathspec per line. Globs work. |
| `exclude-defaults` | `true` | Apply the default exclusions below. |
| `force-zero` | `false` | Reject every dash and opt-out marker in tracked working-tree files, including untouched lines. No base ref needed. |
| `base-ref` | empty | Composite action only: fetched base branch without `origin/`. Empty resolves from the event. |

Set `force-zero: true` once existing dashes are cleared. The reusable workflow
uses checkout depth 1 for this mode, otherwise 2.

## Rules

Banned: U+2010 through U+2015, U+2212, and the HTML entities named `mdash`,
`ndash`, and `minus`. The old opt-out marker (`dash-` followed by `ok`) is also
banned. Exclude paths whose contents you cannot edit; there is no line opt-out.

Only regular tracked files are scanned. Files containing NUL bytes are skipped;
Git attributes cannot exempt text files. Matching uses bytes, regardless of locale.

Default exclusions:

```text
**/node_modules/**   **/*.lock              **/CHANGELOG.md
**/vendor/**         **/package-lock.json   **/LICENSE*
**/.claude/**        **/npm-shrinkwrap.json **/CLAUDE.md
**/.cursor/**        **/pnpm-lock.yaml      **/AGENTS.md
                    **/bun.lockb
                    **/go.sum
```

`exclude` adds to these. `exclude-defaults: false` removes them.

## Composite action

Use for a custom runner, extra steps, or GitHub Enterprise Server:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  with:
    fetch-depth: 2
    persist-credentials: false
- uses: notambourine/dash-ratchet@556a4457c467fb9c28a3240f7f030bf9204cb357 # v0.4.0
```

Depth 2 supplies the PR merge ref's first parent. For another checkout, fetch
the base branch and set `base-ref`. Force-zero needs only depth 1.

## Local use

Run from the repository to check:

```bash
/path/to/dash-ratchet/scripts/check-dashes.sh origin/main  # fetched base
/path/to/dash-ratchet/scripts/check-dashes.sh --staged     # HEAD vs index
/path/to/dash-ratchet/scripts/check-dashes.sh --force-zero # tracked working tree
```

For a local pre-commit hook, put
`exec /path/to/dash-ratchet/scripts/check-dashes.sh --staged` in
`.git/hooks/pre-commit` and make it executable. Hooks are bypassable; keep CI.

## License

MIT
