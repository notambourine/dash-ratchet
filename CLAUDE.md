# Repository rules

- Land changes through squash-merged PRs. Sign commits; never push directly to main.
  Self-merge after required checks pass.
- Keep usage in README. Read code and CI for implementation and check commands.
  Leave CI-covered checks to CI unless iterating on a fix.
- Keep every tracked file free of banned dashes, HTML dash entities, and the
  opt-out marker. Build test fixtures from escapes or fragments.
- Preserve Bash 3.2 compatibility and operation without a UTF-8 locale.
- Recheck the actionlint context suppression when upgrading actionlint; remove
  it once supported.

# Releases

- Run `scripts/release.sh <version>` without a leading `v` from clean, synced main
  after CI succeeds on its tip.
- Run `scripts/release.sh <version> --readme` separately to open the draft pin PR.
- For input changes, supply a short, untracked `RELEASE_NOTES_PREFIX` file with
  upgrade instructions first so Dependabot readers see them.
- Let the release script update README pins; never edit them by hand.
- Never move published tags. Fix a bad release with a patch version.
- Do not publish floating major tags during 0.x.
