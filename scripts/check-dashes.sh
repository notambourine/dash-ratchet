#!/bin/bash
# Unicode-dash ratchet. Three assertions, against the PR's base branch in CI or
# against HEAD in a pre-commit hook:
#
#   1. No added line carries a unicode dash.
#   2. No added line carries an opt-out marker.
#   3. The repo-wide total did not go up.
#
# (1) is the one a contributor reads and fixes, because it names the line. On a
# merge-ref checkout it already sees the whole net effect of the merge, since the
# base tip IS the merge base there.
#
# (2) catches the opt-out marker itself: one that suppresses nothing still reads
# as permission to the next author. Whole paths go in $DASH_EXCLUDE.
#
# (3) is the number that has to keep falling, and the one edit (1) cannot see is
# a base that moved under it: a stale branch reinstating dashes the base already
# removed shows up in no diff hunk. Both counts read trees the depth-2 clone
# already holds, so (3) costs a grep, not a fetch.
#
# The banned character set and the excluded paths ($DASH_EXCLUDE, one pathspec
# per line) live in lib/dash-set.sh next to this script.
#
# Usage: check-dashes.sh [base-ref | --staged]
#
# With no argument the base is resolved from the event. A pull_request checkout
# takes refs/pull/N/merge, whose first parent IS the base tip, so `fetch-depth: 2`
# carries both sides and none of the history between them.
#
# --staged reads the index instead of a ref, for a pre-commit hook: the diff is
# HEAD against what is staged, and the second count reads the index. Local only,
# and bypassed by --no-verify or a clone that never installed the hook, so CI
# stays the gate.
set -euo pipefail

STAGED=0
BASE=""
case "${1:-}" in
--staged) STAGED=1 ;;
*) BASE="${1:-}" ;;
esac

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dash-set.sh
source "$(dirname "$0")/lib/dash-set.sh"

if [ "$STAGED" -eq 1 ]; then
	if git rev-parse --verify --quiet HEAD >/dev/null; then
		BEFORE=HEAD
		BEFORE_LABEL=HEAD
	else
		# Root commit: the empty tree stands in for the HEAD that does not exist yet.
		BEFORE=$(git hash-object -t tree /dev/null)
		BEFORE_LABEL="empty tree"
	fi
	AFTER=:index
	AFTER_LABEL=index
else
	if [ -z "$BASE" ]; then
		# GITHUB_REF, not a parent count: a PR whose own head commit is a merge also
		# has two parents, and there HEAD^1 is not the base.
		case "${GITHUB_REF:-}" in
		refs/pull/*/merge) BASE="HEAD^1" ;;
		*) BASE="origin/${GITHUB_BASE_REF:-main}" ;;
		esac
	fi
	git rev-parse --verify --quiet "$BASE" >/dev/null || {
		if [ "$BASE" = "HEAD^1" ]; then
			echo "::error::the merge ref has no first parent - checkout needs fetch-depth 2 or more"
		else
			echo "::error::base ref '${BASE}' is not fetched - check the workflow's fetch-depth"
		fi
		exit 1
	}
	BEFORE="$BASE"
	BEFORE_LABEL="$BASE"
	AFTER=HEAD
	AFTER_LABEL=HEAD
fi

count_tree() {
	local lines rc=0
	if [ "$1" = ":index" ]; then
		lines=$(git grep -I -h --cached --perl-regexp "${DASH_PCRE[@]}" -- "${DASH_PATHSPEC[@]}") || rc=$?
	else
		lines=$(git grep -I -h --perl-regexp "${DASH_PCRE[@]}" "$1" -- "${DASH_PATHSPEC[@]}") || rc=$?
	fi
	# git grep exit 1 is a clean zero-dash tree. Above that it failed and printed
	# why, so nothing redirects stderr - that turns a fatal into a bare exit code.
	if [ "$rc" -gt 1 ]; then
		echo "::error::git grep failed on '${1}' (exit ${rc}) - the dash count is not trustworthy" >&2
		return "$rc"
	fi
	printf '%s\n' "$lines" |
		perl -ne '
			BEGIN { $re = qr/$ENV{DASH_BYTES}/; $n = 0 }
			$n += () = /$re/g;
			END { print $n + 0 }
		'
}

# report <kind> <findings>: prints the human list, then one annotation per line
# when a workflow is reading. `kind` is the headline the contributor acts on.
report() {
	local kind="$1" findings="$2"
	case "$kind" in
	dash)
		echo "Unicode dashes on added lines. Type an ASCII hyphen instead, or hold the"
		echo "path out of the rule with the exclude input."
		;;
	marker)
		echo "The dash-o""k marker no longer suppresses anything and is banned itself."
		echo "Fix the dash on the line, or hold the path out with the exclude input."
		;;
	esac
	echo
	printf '%s\n' "$findings"
	[ "$STAGED" -eq 1 ] && return 0
	printf '%s\n' "$findings" | while IFS=: read -r file line text; do
		echo "::error file=${file},line=${line},title=Unicode dash::${text}"
	done
}

status=0

# ---- 1 + 2. no dash and no marker on an added line -------------------------
if [ "$STAGED" -eq 1 ]; then
	diff_cmd=(git diff --cached --no-color -U0 "$BEFORE")
else
	diff_cmd=(git diff --no-color -U0 "${BASE}...HEAD")
fi
# One walk, two verdicts: the kind leads each record so bash can split them.
found=$(
	"${diff_cmd[@]}" -- "${DASH_PATHSPEC[@]}" |
		perl -ne '
			BEGIN { $re = qr/$ENV{DASH_BYTES}/; $mre = qr/$ENV{DASH_MARKER_BYTES}/ }
			if (/^\+\+\+ b\/(.*)/) { $file = $1; next }
			# -U0, so every line after a hunk header is an add or a delete and
			# only the adds advance the new-file line number.
			if (/^\@\@ .*? \+(\d+)/) { $line = $1; next }
			next unless /^\+/;
			my $text = substr($_, 1);
			printf("dash\t%s:%d:%s", $file, $line, $text) if $text =~ $re;
			printf("marker\t%s:%d:%s", $file, $line, $text) if $text =~ $mre;
			$line++;
		'
)
for kind in dash marker; do
	hits=$(printf '%s\n' "$found" | sed -n "s/^${kind}	//p")
	if [ -n "$hits" ]; then
		report "$kind" "$hits"
		status=1
	fi
done

# ---- 3. repo-wide total did not rise ---------------------------------------
before=$(count_tree "$BEFORE")
after=$(count_tree "$AFTER")
delta=$((after - before))
sign=""
[ "$delta" -gt 0 ] && sign="+"
echo
echo "unicode dashes: ${BEFORE_LABEL} ${before} -> ${AFTER_LABEL} ${after} (${sign}${delta})"

# The job log is the one place nobody opens, so the count also goes to the run
# summary, which renders on the checks page without expanding a step.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Unicode dashes"
		echo
		echo "\`${BEFORE_LABEL}\` ${before} to \`${AFTER_LABEL}\` ${after} (**${sign}${delta}**)"
		if [ "$delta" -gt 0 ]; then
			echo
			echo "The total rose. This count only ever goes down."
		fi
	} >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$delta" -gt 0 ]; then
	msg="the unicode-dash total rose by ${delta} - this count only ever goes down"
	if [ "$STAGED" -eq 1 ]; then
		echo "$msg" >&2
	else
		echo "::error::${msg}"
	fi
	status=1
fi

exit "$status"
