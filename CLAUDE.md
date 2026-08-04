# dash-ratchet

Published GitHub Action + reusable workflow. Consumers pin a commit SHA; the
README owns usage. This file owns how to cut a release and what may be edited
where.

## Release

Run `scripts/release.sh <version>` (no leading `v`) from a clean, synced main.
It verifies CI is green on the exact tip, tags `v<version>`, publishes
generated release notes, then re-pins the README examples to the tag commit
through a squash-merged PR.

The bump map - where versions and SHAs live:

- `README.md` usage pins (two `@<sha> # v<version>` lines plus one prose
  mention of the tag) are the ONLY derived SHAs in the repo, and release.sh
  owns them. Invariant: a commit cannot contain its own SHA, so main's README
  points at the latest tag and each tag's README points at the release before
  it. Never hand-edit the pins.
- `.github/workflows/ratchet.yml` needs no release bump: it checks out its own
  source at `job.workflow_sha`, the ref the caller pinned.
- `actions/checkout` pins and the actionlint/zizmor versions + sha256 in
  `ci.yml` are dependency bumps, not release bumps.

Tags are immutable by ruleset. A bad release gets the next patch version,
never a moved tag. No floating `v0` major tag while 0.x.

## Main is locked

PR-only (squash, zero approvals), force-push and deletion blocked on every
branch, signed commits required, no bypass actors, merged branches
auto-delete. That is why release.sh routes the README bump through a PR.
GitHub refuses push rulesets on public repos, so there is no workflow fence;
`.github/workflows/` edits ride the same PR gate as everything else.

## Repo rules

- No literal unicode dash lands in this tree; the dogfood CI job gates it.
  Test fixtures build dashes from byte escapes at runtime. A line that must
  carry one takes the `dash-ok` marker.
- Everything runs on `ubuntu-slim`: bash, git, perl, curl only, no UTF-8
  locale (the reason for `(*UTF)` in `scripts/lib/dash-set.sh`), 15-minute
  hard kill.
- `.github/actionlint.yaml` suppresses the `job.workflow_sha` /
  `job.workflow_repository` context warning because actionlint's schema lags
  the real context. On an actionlint bump, re-check and drop the ignore once
  it knows the properties.
- Before pushing: `shellcheck -x scripts/*.sh scripts/lib/*.sh test/run.sh`,
  `actionlint`, `zizmor .`, and `test/run.sh` (runs itself under both the
  ambient locale and `LC_ALL=C`).
