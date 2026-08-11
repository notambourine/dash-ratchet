#!/bin/bash
# Unicode-dash ratchet. Two assertions against the PR's base branch:
#
#   1. No line the PR adds carries a unicode dash.
#   2. The repo-wide total did not go up.
#
# (1) is the one a contributor reads and fixes, because it names the line. On a
# merge-ref checkout it already sees the whole net effect of the merge, since the
# base tip IS the merge base there.
#
# (2) is the number that has to keep falling, and the one edit (1) cannot see is
# a base that moved under it: a stale branch reinstating dashes the base already
# removed shows up in no diff hunk. Both counts read trees the depth-2 clone
# already holds, so (2) costs a grep, not a fetch.
#
# The banned character set, the marker (default `dash-ok`, override with
# $DASH_MARKER), and the excluded trees ($DASH_EXCLUDE, one directory per line)
# all live in lib/dash-set.sh next to this script.
#
# Usage: check-dashes.sh [base-ref]
#
# With no argument the base is resolved from the event. A pull_request checkout
# takes refs/pull/N/merge, whose first parent IS the base tip, so `fetch-depth: 2`
# carries both sides and none of the history between them.
set -euo pipefail

BASE="${1:-}"
if [ -z "$BASE" ]; then
	# GITHUB_REF, not a parent count: a PR whose own head commit is a merge also
	# has two parents, and there HEAD^1 is not the base.
	case "${GITHUB_REF:-}" in
	refs/pull/*/merge) BASE="HEAD^1" ;;
	*) BASE="origin/${GITHUB_BASE_REF:-main}" ;;
	esac
fi

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dash-set.sh
source "$(dirname "$0")/lib/dash-set.sh"

git rev-parse --verify --quiet "$BASE" >/dev/null || {
	if [ "$BASE" = "HEAD^1" ]; then
		echo "::error::the merge ref has no first parent - checkout needs fetch-depth 2 or more"
	else
		echo "::error::base ref '${BASE}' is not fetched - check the workflow's fetch-depth"
	fi
	exit 1
}

count_rev() {
	local lines rc=0
	lines=$(git grep -I -h --perl-regexp "${DASH_PCRE[@]}" "$1" -- "${DASH_PATHSPEC[@]}") || rc=$?
	# git grep exit 1 is a clean zero-dash tree. Above that it failed and printed
	# why, so nothing redirects stderr - that turns a fatal into a bare exit code.
	if [ "$rc" -gt 1 ]; then
		echo "::error::git grep failed on '${1}' (exit ${rc}) - the dash count is not trustworthy" >&2
		return "$rc"
	fi
	printf '%s\n' "$lines" |
		perl -ne '
			BEGIN { $re = qr/$ENV{DASH_BYTES}/; $m = $ENV{DASH_MARKER}; $n = 0 }
			next if index($_, $m) >= 0;
			$n += () = /$re/g;
			END { print $n + 0 }
		'
}

status=0

# ---- 1. no dash on an added line -------------------------------------------
added=$(
	git diff --no-color -U0 "${BASE}...HEAD" -- "${DASH_PATHSPEC[@]}" |
		perl -ne '
			BEGIN { $re = qr/$ENV{DASH_BYTES}/; $m = $ENV{DASH_MARKER} }
			if (/^\+\+\+ b\/(.*)/) { $file = $1; next }
			# -U0, so every line after a hunk header is an add or a delete and
			# only the adds advance the new-file line number.
			if (/^\@\@ .*? \+(\d+)/) { $line = $1; next }
			next unless /^\+/;
			my $text = substr($_, 1);
			printf("%s:%d:%s", $file, $line, $text)
				if $text =~ $re && index($text, $m) < 0;
			$line++;
		'
)
if [ -n "$added" ]; then
	echo "Unicode dashes on lines this PR adds. Type an ASCII hyphen instead, or"
	echo "put ${DASH_MARKER} on the line when the character is load-bearing."
	echo
	printf '%s\n' "$added"
	printf '%s\n' "$added" | while IFS=: read -r file line text; do
		echo "::error file=${file},line=${line},title=Unicode dash::${text}"
	done
	status=1
fi

# ---- 2. repo-wide total did not rise ---------------------------------------
before=$(count_rev "$BASE")
after=$(count_rev HEAD)
delta=$((after - before))
sign=""
[ "$delta" -gt 0 ] && sign="+"
echo
echo "unicode dashes: ${BASE} ${before} -> HEAD ${after} (${sign}${delta})"

# The job log is the one place nobody opens, so the count also goes to the run
# summary, which renders on the checks page without expanding a step.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Unicode dashes"
		echo
		echo "\`${BASE}\` ${before} to \`HEAD\` ${after} (**${sign}${delta}**)"
		if [ "$delta" -gt 0 ]; then
			echo
			echo "The total rose. This count only ever goes down."
		fi
	} >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$delta" -gt 0 ]; then
	echo "::error::the unicode-dash total rose by ${delta} - this count only ever goes down"
	status=1
fi

exit "$status"
