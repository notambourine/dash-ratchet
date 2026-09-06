#!/bin/bash
set -euo pipefail

ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
export RELEASE_SCRIPT="$ROOT/scripts/release.sh"
export REAL_GIT
REAL_GIT=$(command -v git)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
export RELEASE_LOG="$TMP/gh.log"

cat >"$TMP/bin/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$RELEASE_LOG"
case "$1 $2" in
'run list') echo "${CI_RESULT:-success}" ;;
'release create') ;;
'pr create')
	[[ " $* " = *' --draft '* ]] || exit 1
	while [ "$#" -gt 0 ]; do
		if [ "$1" = --body-file ]; then
			cat "$2" >>"$RELEASE_LOG"
			break
		fi
		shift
	done
	;;
*) exit 1 ;;
esac
EOF
cat >"$TMP/bin/gtimeout" <<'EOF'
#!/bin/bash
[ "${PUSH_TIMEOUT:-false}" = true ] && exit 124
shift
exec "$@"
EOF
cat >"$TMP/bin/git" <<'EOF'
#!/bin/bash
if [ "${1:-}" = -C ] && [ "${3:-}" = commit ] && [ "${4:-}" = -S ]; then
	root="$2"
	shift 4
	exec "$REAL_GIT" -C "$root" -c commit.gpgsign=false commit "$@"
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$TMP/bin/gh" "$TMP/bin/gtimeout" "$TMP/bin/git"
export PATH="$TMP/bin:$PATH"
export RELEASE_TEST_PATH="$PATH"

new_repo() {
	REPO="$TMP/$1"
	REMOTE="$TMP/$1.git"
	git init -q --bare -b main "$REMOTE"
	git init -q -b main "$REPO"
	git -C "$REPO" config user.name test
	git -C "$REPO" config user.email test@example.com
	cp "$ROOT/README.md" "$REPO/README.md"
	git -C "$REPO" add README.md
	git -C "$REPO" commit -qm base
	git -C "$REPO" remote add origin "$REMOTE"
	gtimeout 15 git -C "$REPO" push -qu origin main
	: >"$RELEASE_LOG"
}

run_case() {
	local name="$1" expected="$2" match="$3" rc=0 out
	shift 3
	out=$(git -C "$REPO" -c "alias.release=!env PATH=\"\$RELEASE_TEST_PATH\" /bin/bash \"\$RELEASE_SCRIPT\"" release "$@" 2>&1) || rc=$?
	if [ "$rc" -ne "$expected" ] || [[ "$out" != *"$match"* ]]; then
		printf 'FAIL %s (exit %s, expected %s)\n%s\n' "$name" "$rc" "$expected" "$out"
		exit 1
	fi
	echo "ok   release: $name"
}

expect_absent() {
	local rc=0
	"$@" || rc=$?
	if [ "$rc" -ne 1 ]; then
		echo "FAIL expected absence (exit $rc): $*"
		exit 1
	fi
}

no_remote_tag() {
	if git -C "$REMOTE" show-ref --verify --quiet refs/tags/v0.4.0; then
		echo 'FAIL release published a tag after failed preflight'
		exit 1
	fi
}

new_repo version
run_case 'invalid version stops before publishing' 1 'expected a version' v0.4.0
no_remote_tag
export RELEASE_NOTES_PREFIX="$TMP/missing"
run_case 'missing notes stop before publishing' 1 'is not a file' 0.4.0
unset RELEASE_NOTES_PREFIX
no_remote_tag

new_repo drift
perl -ni -e 'print unless /tag points at/' "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm drift
gtimeout 15 git -C "$REPO" push -q origin main
run_case 'README drift stops before publishing' 255 'README pin pattern drift' 0.4.0
no_remote_tag
expect_absent git -C "$REPO" show-ref --verify --quiet refs/tags/v0.4.0

new_repo ci
export CI_RESULT=failure
run_case 'failed CI stops before publishing' 1 'not success' 0.4.0
unset CI_RESULT
no_remote_tag

new_repo timeout
export PUSH_TIMEOUT=true
run_case 'push timeout skips release creation' 124 'remaining steps skipped' 0.4.0
unset PUSH_TIMEOUT
no_remote_tag
expect_absent grep -q 'release create' "$RELEASE_LOG"

new_repo publish
run_case 'publishing leaves README on main' 0 'released v0.4.0' 0.4.0
git -C "$REMOTE" show-ref --verify --quiet refs/tags/v0.4.0
git -C "$REPO" diff --quiet
[ "$(git -C "$REPO" branch --show-current)" = main ]
expect_absent grep -q 'pr create' "$RELEASE_LOG"

: >"$RELEASE_LOG"
run_case 'README update creates a separate draft PR' 0 '' 0.4.0 --readme
[ "$(git -C "$REPO" branch --show-current)" = release/readme-v0.4.0 ]
sha=$(git -C "$REPO" rev-parse 'v0.4.0^{commit}')
[ "$(grep -c "@${sha} # v0.4.0" "$REPO/README.md")" -eq 2 ]
grep -Fq "the \`v0.4.0\` tag points at" "$REPO/README.md"
grep -q 'pr create --draft' "$RELEASE_LOG"
expect_absent grep -q 'release create' "$RELEASE_LOG"
expect_absent grep -q 'pr merge' "$RELEASE_LOG"
echo 'release cases passed'
