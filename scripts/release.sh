#!/bin/bash
# Cut a release: tag the current main tip, publish generated release notes,
# then re-pin the README usage examples to the new tag commit through a
# squash-merged PR (main only takes PRs).
#
# A commit cannot contain its own SHA, so main's README always points at the
# LATEST tag and each tag's own README points at the release before it. The
# README pin lines are the only derived SHAs in this repo; everything else
# resolves itself (the reusable workflow via job.workflow_sha).
#
# Usage: scripts/release.sh <version>     e.g. scripts/release.sh 0.2.0
set -euo pipefail

V="${1:?usage: scripts/release.sh <version, no leading v>}"
case "$V" in
v*) echo "version without the leading v: ${V}" >&2; exit 1 ;;
esac
TAG="v${V}"

if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "dirty tree" >&2
	exit 1
fi
BRANCH=$(git symbolic-ref --short HEAD)
[ "$BRANCH" = main ] || { echo "release from main, not ${BRANCH}" >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
	{ echo "main is not in sync with origin/main" >&2; exit 1; }

SHA=$(git rev-parse HEAD)

CONC=$(gh run list --commit "$SHA" --workflow CI --json conclusion \
	-q '.[0].conclusion' 2>/dev/null || echo none)
[ "$CONC" = success ] || { echo "CI on ${SHA} is '${CONC}', not success" >&2; exit 1; }

git tag -a "$TAG" -m "dash-ratchet ${V}" "$SHA"
git push origin "$TAG"
gh release create "$TAG" --verify-tag --generate-notes

BUMP="release/readme-${TAG}"
git checkout -qb "$BUMP"
perl -pi -e "s{(notambourine/dash-ratchet(?:/\\.github/workflows/ratchet\\.yml)?\@)[0-9a-f]{40} # v[0-9.]+}{\${1}${SHA} # ${TAG}}g" README.md
perl -pi -e "s{the \`v[0-9.]+\` tag points at}{the \`${TAG}\` tag points at}" README.md
git diff --quiet README.md && { echo "README pins did not change - pattern drift?" >&2; exit 1; }
git commit -qam "README: pin usage examples to ${TAG}"
git push -q -u origin "$BUMP"
gh pr create --title "README: pin usage examples to ${TAG}" \
	--body "Re-pins the README usage examples to ${TAG} (${SHA}). Cut by scripts/release.sh."

# A fresh PR takes a moment to become mergeable; branch auto-deletes on merge.
merged=""
for _ in 1 2 3 4 5; do
	if gh pr merge "$BUMP" --squash --delete-branch 2>/dev/null; then
		merged=1
		break
	fi
	sleep 5
done
[ -n "$merged" ] || { echo "merge did not land; finish with: gh pr merge ${BUMP} --squash --delete-branch" >&2; exit 1; }

git checkout -q main
git pull -q origin main
echo "released ${TAG} at ${SHA}; README pins updated on main"
