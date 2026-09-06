#!/bin/bash
set -euo pipefail

V="${1:?usage: scripts/release.sh <version, no leading v> [--readme]}"
MODE="${2:-publish}"
NUMBER='(0|[1-9][0-9]*)'
if [ "$#" -gt 2 ] || [[ ! "$V" =~ ^${NUMBER}\.${NUMBER}\.${NUMBER}$ ]]; then
	echo "expected a version such as 0.4.0, without a leading v" >&2
	exit 1
fi
case "$MODE" in
publish|--readme) ;;
*) echo "unknown release option: ${MODE}" >&2; exit 1 ;;
esac
TAG="v${V}"
ROOT=$(git rev-parse --show-toplevel)
git() { command git -C "$ROOT" "$@"; }

push() {
	local rc=0
	gtimeout 15 git -C "$ROOT" push "$@" || rc=$?
	if [ "$rc" -eq 124 ]; then
		echo "push timed out; remote state is unknown; remaining steps skipped" >&2
	fi
	return "$rc"
}

NOTES=(--generate-notes)
if [ "$MODE" = publish ] && [ -n "${RELEASE_NOTES_PREFIX:-}" ]; then
	[ -f "$RELEASE_NOTES_PREFIX" ] ||
		{ echo "RELEASE_NOTES_PREFIX is not a file: ${RELEASE_NOTES_PREFIX}" >&2; exit 1; }
	NOTES+=(--notes-file "$RELEASE_NOTES_PREFIX")
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "dirty tree" >&2
	exit 1
fi
BRANCH=$(git symbolic-ref --short HEAD)
[ "$BRANCH" = main ] || { echo "release from main, not ${BRANCH}" >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
	{ echo "main is not in sync with origin/main" >&2; exit 1; }

if [ "$MODE" = --readme ]; then
	git fetch -q origin "refs/tags/${TAG}:refs/tags/${TAG}"
	SHA=$(git rev-parse "${TAG}^{commit}")
else
	SHA=$(git rev-parse HEAD)
	CONC=$(gh run list --commit "$SHA" --workflow CI --branch main --event push --limit 1 \
		--json conclusion -q '.[0].conclusion')
	[ "$CONC" = success ] || { echo "CI on ${SHA} is '${CONC}', not success" >&2; exit 1; }
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Validate the complete replacement before publishing an immutable tag.
TAG="$TAG" SHA="$SHA" perl -0777 -e '
	my $text = <>;
	my %seen;
	my $pins = $text =~ s{(notambourine/dash-ratchet(?:/\.github/workflows/ratchet\.yml)?\@)[0-9a-f]{40} # v[0-9.]+}{
		$seen{$1}++; $1 . $ENV{SHA} . " # " . $ENV{TAG}
	}ge;
	my $prose = $text =~ s{the `v[0-9.]+` tag points at}{"the `" . $ENV{TAG} . "` tag points at"}ge;
	die "README pin pattern drift\n" unless $pins == 2 && keys(%seen) == 2 && $prose == 1;
	print $text;
' "$ROOT/README.md" >"$TMP/README.md"

if [ "$MODE" = publish ]; then
	git tag -a "$TAG" -m "dash-ratchet ${V}" "$SHA"
	push origin "$TAG"
	gh release create "$TAG" --verify-tag "${NOTES[@]}"
	echo "released ${TAG} at ${SHA}; create the README PR with scripts/release.sh ${V} --readme"
	exit 0
fi

cmp -s "$ROOT/README.md" "$TMP/README.md" && { echo "README already pins ${TAG}"; exit 0; }
BUMP="release/readme-${TAG}"
git checkout -qb "$BUMP"
cp "$TMP/README.md" "$ROOT/README.md"
git add README.md
git commit -S -m "README: pin usage examples to ${TAG}"
push -u origin "$BUMP"
cat >"$TMP/pr.md" <<EOF
## Goal

Pin usage examples to ${TAG} (${SHA}).

## Summary

- **Usage:** both examples use the published commit.

## Key Decisions

Keep release publishing separate from this README update.

## Test Plan

- [x] Validated both usage pins and the tag reference before editing.
- [ ] CI pending.
EOF
gh pr create --draft --base main --head "$BUMP" \
	--title "README: pin usage examples to ${TAG}" --body-file "$TMP/pr.md"
