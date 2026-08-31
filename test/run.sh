#!/bin/bash
# Behavior tests for scripts/check-dashes.sh. Each case builds a throwaway git
# repo with a base branch and a pr branch, runs the gate, and asserts the exit
# code plus one output substring.
#
# The whole suite runs twice: once under the ambient locale and once under
# LC_ALL=C, because a container runner sets no UTF-8 locale and the counts
# must not move. No unicode dash is committed to THIS repo: fixture dashes are
# built at runtime from byte escapes, which keeps the repo's own gate at zero.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/check-dashes.sh"
EM="$(printf '\xe2\x80\x94')"
# Both fixtures are assembled here for the same reason: a literal em dash, HTML
# dash entity, or opt-out marker in this file would trip the repo's own gate.
ENTITY="$(printf '&%s;' mdash)"
MARKER="$(printf 'dash-%sk' o)"

# Hermetic git: the user's config (signing, hooks, templates) must not leak in.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
cases=0
LOCALE_TAG=ambient

new_repo() {
	REPO="$TMP/${LOCALE_TAG}-$1"
	git init -q -b main "$REPO"
	git -C "$REPO" config user.email test@example.com
	git -C "$REPO" config user.name test
}

commit_all() {
	git -C "$REPO" add -A
	git -C "$REPO" commit -qm "$1"
}

# run_case <name> <want-rc> <output-substring>: runs the gate in $REPO vs main.
# $CHECK_ARG overrides the argument; $CHECK_REF sets the GITHUB_REF instead.
run_case() {
	local name="$1" want_rc="$2" want_out="$3" out rc ok=1
	cases=$((cases + 1))
	if [ -n "${CHECK_ARG:-}" ]; then
		out=$(cd "$REPO" && "$CHECK" "$CHECK_ARG" 2>&1)
	elif [ -n "${CHECK_REF:-}" ]; then
		out=$(cd "$REPO" && GITHUB_REF="$CHECK_REF" "$CHECK" 2>&1)
	else
		out=$(cd "$REPO" && "$CHECK" main 2>&1)
	fi
	rc=$?
	[ "$rc" -eq "$want_rc" ] || ok=0
	case "$out" in *"$want_out"*) ;; *) ok=0 ;; esac
	if [ "$ok" -eq 1 ]; then
		echo "ok   ${LOCALE_TAG}: ${name}"
	else
		fails=$((fails + 1))
		echo "FAIL ${LOCALE_TAG}: ${name} (rc=${rc} want=${want_rc}, output must contain '${want_out}')"
		printf '%s\n' "$out" | sed 's/^/     /'
	fi
}

suite() {
	# 1. a dash on an added line fails and names the line
	new_repo added
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	printf 'bad %s line\n' "$EM" >"$REPO/b.txt"
	commit_all head
	run_case "added dash fails, names the line" 1 "::error file=b.txt,line=1"

	# 2. the opt-out marker is banned, dash or no dash on the line
	new_repo marker
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	printf 'kept %s line %s\n' "$EM" "$MARKER" >"$REPO/b.txt"
	commit_all head
	run_case "marker line fails" 1 "marker no longer suppresses"

	new_repo marker-alone
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	printf 'no dash here %s\n' "$MARKER" >"$REPO/b.txt"
	commit_all head
	run_case "bare marker fails with a zero count" 1 "marker no longer suppresses"

	# 3. a rise the diff cannot see: base cleaned its dashes after the branch
	# point, so only the repo-wide backstop can catch the stale head.
	new_repo rise
	printf 'two %s %s here\n' "$EM" "$EM" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	echo "unrelated" >"$REPO/c.txt"
	commit_all head
	git -C "$REPO" checkout -q main
	echo "cleaned" >"$REPO/a.txt"
	commit_all cleanup
	git -C "$REPO" checkout -q pr
	run_case "total rise fails via the backstop" 1 "total rose by 2"

	# 4. a falling total passes and prints the drop
	new_repo fall
	printf 'two %s %s here\n' "$EM" "$EM" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	echo "cleaned" >"$REPO/a.txt"
	commit_all head
	run_case "total fall passes" 0 "main 2 -> HEAD 0 (-2)"

	# 5. an excluded tree is outside the rule for both assertions
	new_repo exclude
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	mkdir "$REPO/vendor"
	printf 'wire %s bytes\n' "$EM" >"$REPO/vendor/fixture.txt"
	commit_all head
	export DASH_EXCLUDE=vendor
	run_case "excluded dir is ignored" 0 "main 0 -> HEAD 0 (0)"
	unset DASH_EXCLUDE

	# 5b. the built-in hold-out list, on by default and off on request. A
	# lockfile at depth and an agent file at the root cover both glob shapes.
	new_repo defaults
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	mkdir -p "$REPO/web"
	printf 'dep %s note\n' "$EM" >"$REPO/web/package-lock.json"
	printf 'agent %s note\n' "$EM" >"$REPO/CLAUDE.md"
	commit_all head
	run_case "default hold-outs are ignored" 0 "main 0 -> HEAD 0 (0)"
	export DASH_EXCLUDE_DEFAULTS=false
	run_case "exclude-defaults false gates them" 1 "::error file=CLAUDE.md,line=1"
	export DASH_EXCLUDE_DEFAULTS=maybe
	run_case "a non-boolean is a hard error" 1 "takes true or false"
	unset DASH_EXCLUDE_DEFAULTS

	# 6. HTML dash entities are part of the banned set
	new_repo entity
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	printf 'an %s entity\n' "$ENTITY" >"$REPO/b.txt"
	commit_all head
	run_case "html entity fails" 1 "::error file=b.txt,line=1"

	# 7. a zero-dash tree passes (git grep exits 1 there; that is not an error)
	new_repo zero
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	echo "also clean" >"$REPO/b.txt"
	commit_all head
	run_case "zero-dash tree passes" 0 "main 0 -> HEAD 0 (0)"

	# 8-9. a merge commit standing in for refs/pull/N/merge. No origin/<base>
	# exists here, which is what a fetch-depth 2 clone looks like.
	CHECK_REF=refs/pull/1/merge

	new_repo mergeref
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	printf 'bad %s line\n' "$EM" >"$REPO/b.txt"
	commit_all head
	git -C "$REPO" checkout -q main
	git -C "$REPO" merge -q --no-ff -m merge pr
	run_case "merge ref resolves the base to HEAD^1" 1 "::error file=b.txt,line=1"

	new_repo mergeref-clean
	echo "clean" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	echo "also clean" >"$REPO/b.txt"
	commit_all head
	git -C "$REPO" checkout -q main
	git -C "$REPO" merge -q --no-ff -m merge pr
	run_case "clean merge ref passes" 0 "HEAD^1 0 -> HEAD 0 (0)"

	unset CHECK_REF

	# 10-12. --staged reads the index, so a dash fails before the commit exists
	CHECK_ARG=--staged

	new_repo staged
	echo "clean" >"$REPO/a.txt"
	commit_all base
	printf 'bad %s line\n' "$EM" >"$REPO/b.txt"
	git -C "$REPO" add -A
	run_case "staged dash fails" 1 "HEAD 0 -> index 1 (+1)"

	new_repo staged-clean
	echo "clean" >"$REPO/a.txt"
	commit_all base
	echo "also clean" >"$REPO/b.txt"
	git -C "$REPO" add -A
	run_case "staged clean tree passes" 0 "HEAD 0 -> index 0 (0)"

	# No HEAD to diff against, so the empty tree stands in for it.
	new_repo staged-root
	printf 'bad %s line\n' "$EM" >"$REPO/a.txt"
	git -C "$REPO" add -A
	run_case "staged root commit fails" 1 "empty tree 0 -> index 1 (+1)"

	# An unstaged dash is not this commit's problem.
	new_repo staged-unstaged
	echo "clean" >"$REPO/a.txt"
	commit_all base
	echo "staged and clean" >"$REPO/b.txt"
	git -C "$REPO" add -A
	printf 'bad %s line\n' "$EM" >"$REPO/c.txt"
	run_case "unstaged dash is ignored" 0 "HEAD 0 -> index 0 (0)"

	unset CHECK_ARG

	# 13-16. --force-zero: one tree, no base, so a single-commit repo with no
	# remote is the shape a depth-1 checkout gives the gate.
	CHECK_ARG=--force-zero

	new_repo zero-clean
	echo "clean" >"$REPO/a.txt"
	commit_all base
	run_case "force-zero passes with no base ref at all" 0 "working tree 0, and this gate requires 0"

	new_repo zero-dash
	printf 'bad %s line\n' "$EM" >"$REPO/a.txt"
	commit_all base
	run_case "force-zero names an untouched dash" 1 "::error file=a.txt,line=1"

	new_repo zero-marker
	printf 'no dash here %s\n' "$MARKER" >"$REPO/a.txt"
	commit_all base
	run_case "force-zero fails on the marker" 1 "marker no longer suppresses"

	new_repo zero-held-out
	mkdir "$REPO/web"
	printf 'dep %s note\n' "$EM" >"$REPO/web/package-lock.json"
	commit_all base
	run_case "force-zero honors the hold-out list" 0 "working tree 0"

	unset CHECK_ARG

	# 17. the count reaches the run summary, not just the job log
	new_repo summary
	printf 'two %s %s here\n' "$EM" "$EM" >"$REPO/a.txt"
	commit_all base
	git -C "$REPO" checkout -qb pr
	echo "cleaned" >"$REPO/a.txt"
	commit_all head
	GITHUB_STEP_SUMMARY="$TMP/${LOCALE_TAG}-summary.md"
	export GITHUB_STEP_SUMMARY
	run_case "count reaches the job log" 0 "main 2 -> HEAD 0 (-2)"
	cases=$((cases + 1))
	if grep -q '(\*\*-2\*\*)' "$GITHUB_STEP_SUMMARY" 2>/dev/null; then
		echo "ok   ${LOCALE_TAG}: count reaches the run summary"
	else
		fails=$((fails + 1))
		echo "FAIL ${LOCALE_TAG}: count reaches the run summary (${GITHUB_STEP_SUMMARY})"
	fi
	unset GITHUB_STEP_SUMMARY
}

suite
LOCALE_TAG=C
export LC_ALL=C LANG=C
suite

echo
echo "${cases} cases, ${fails} failed"
[ "$fails" -eq 0 ]
