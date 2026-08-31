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
# Usage: check-dashes.sh [base-ref] [--staged] [--force-zero]
#
# With no argument the base is resolved from the event. A pull_request checkout
# takes refs/pull/N/merge, whose first parent IS the base tip, so `fetch-depth: 2`
# carries both sides and none of the history between them.
#
# --staged reads the index instead of a ref, for a pre-commit hook: the diff is
# HEAD against what is staged, and the second count reads the index. Local only,
# and bypassed by --no-verify or a clone that never installed the hook, so CI
# stays the gate.
#
# --force-zero replaces all three assertions with one: this tree carries no dash
# and no marker at all. For a repo already at zero, where a ratchet has nothing
# to compare - no base ref, no second tree, so `fetch-depth: 1` and one grep.
# It reads no diff, so it also catches a dash the PR did not touch.
set -euo pipefail

STAGED=0
ZERO=0
BASE=""
for _arg in "$@"; do
	case "$_arg" in
	--staged) STAGED=1 ;;
	--force-zero) ZERO=1 ;;
	-*)
		echo "unknown flag: ${_arg}" >&2
		exit 1
		;;
	*) BASE="$_arg" ;;
	esac
done
unset _arg

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/dash-set.sh
source "$(dirname "$0")/lib/dash-set.sh"

if [ "$ZERO" -eq 1 ]; then
	# One tree, so nothing to resolve: the index when staged, else the checkout.
	if [ "$STAGED" -eq 1 ]; then
		AFTER=:index
		AFTER_LABEL=index
	else
		AFTER=:worktree
		AFTER_LABEL="working tree"
	fi
elif [ "$STAGED" -eq 1 ]; then
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
	case "$1" in
	:index) lines=$(git grep -I -h --cached --perl-regexp "${DASH_PCRE[@]}" -- "${DASH_PATHSPEC[@]}") || rc=$? ;;
	:worktree) lines=$(git grep -I -h --perl-regexp "${DASH_PCRE[@]}" -- "${DASH_PATHSPEC[@]}") || rc=$? ;;
	*) lines=$(git grep -I -h --perl-regexp "${DASH_PCRE[@]}" "$1" -- "${DASH_PATHSPEC[@]}") || rc=$? ;;
	esac
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
	local kind="$1" findings="$2" title
	case "$kind" in
	dash)
		title="Unicode dash"
		if [ "$ZERO" -eq 1 ]; then
			echo "Unicode dashes in this tree, which this gate requires to carry none."
		else
			echo "Unicode dashes on added lines."
		fi
		echo "Type an ASCII hyphen instead, or hold the path out with the exclude input."
		;;
	marker)
		title="Opt-out marker"
		echo "The dash-o""k marker no longer suppresses anything and is banned itself."
		echo "Fix the dash on the line, or hold the path out with the exclude input."
		;;
	esac
	echo
	printf '%s\n' "$findings"
	[ "$STAGED" -eq 1 ] && return 0
	printf '%s\n' "$findings" | while IFS=: read -r file line text; do
		echo "::error file=${file},line=${line},title=${title}::${text}"
	done
}

status=0

# ---- 1 + 2. no dash and no marker, on an added line or anywhere ------------
# Both walks emit the same `kind<tab>file:line:text`, so one loop reports either.
if [ "$ZERO" -eq 1 ]; then
	grep_cmd=(git grep -I -n --perl-regexp)
	[ "$STAGED" -eq 1 ] && grep_cmd+=(--cached)
	rc=0
	found=$(
		"${grep_cmd[@]}" "${DASH_PCRE[@]}" -e "$DASH_MARKER_BYTES" \
			-- "${DASH_PATHSPEC[@]}" |
			perl -ne '
				BEGIN { $mre = qr/$ENV{DASH_MARKER_BYTES}/ }
				# git grep only returned matching lines, so anything the marker
				# misses is a dash. Marker first, as in the diff walk below.
				my ($pfx, $text) = /^(.*?:\d+:)(.*)$/s or next;
				printf("%s\t%s%s", $text =~ $mre ? "marker" : "dash", $pfx, $text);
			'
	) || rc=$?
	if [ "$rc" -gt 1 ]; then
		echo "::error::git grep failed (exit ${rc}) - the result is not trustworthy" >&2
		exit "$rc"
	fi
else
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
			# A line can hit both. The marker text also asks for the dash, so it wins:
			# naming the dash alone leaves the marker to fail the next run.
			if ($text =~ $mre) { printf("marker\t%s:%d:%s", $file, $line, $text) }
			elsif ($text =~ $re) { printf("dash\t%s:%d:%s", $file, $line, $text) }
			$line++;
		'
	)
fi
for kind in dash marker; do
	hits=$(printf '%s\n' "$found" | sed -n "s/^${kind}	//p")
	if [ -n "$hits" ]; then
		report "$kind" "$hits"
		status=1
	fi
done

# ---- 3. the total did not rise, or is zero under --force-zero --------------
after=$(count_tree "$AFTER")
if [ "$ZERO" -eq 1 ]; then
	headline="${AFTER_LABEL} ${after}, and this gate requires 0"
	summary="\`${AFTER_LABEL}\` **${after}**, and this gate requires 0"
	[ "$after" -gt 0 ] && status=1
else
	before=$(count_tree "$BEFORE")
	delta=$((after - before))
	sign=""
	[ "$delta" -gt 0 ] && sign="+"
	headline="${BEFORE_LABEL} ${before} -> ${AFTER_LABEL} ${after} (${sign}${delta})"
	summary="\`${BEFORE_LABEL}\` ${before} to \`${AFTER_LABEL}\` ${after} (**${sign}${delta}**)"
fi
echo
echo "unicode dashes: ${headline}"

# The job log is the one place nobody opens, so the count also goes to the run
# summary, which renders on the checks page without expanding a step.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Unicode dashes"
		echo
		echo "$summary"
		if [ "$ZERO" -eq 0 ] && [ "$delta" -gt 0 ]; then
			echo
			echo "The total rose. This count only ever goes down."
		fi
	} >>"$GITHUB_STEP_SUMMARY"
fi

# Under --force-zero every dash already carries its own annotation, so the count
# needs no second error line.
if [ "$ZERO" -eq 0 ] && [ "$delta" -gt 0 ]; then
	msg="the unicode-dash total rose by ${delta} - this count only ever goes down"
	if [ "$STAGED" -eq 1 ]; then
		echo "$msg" >&2
	else
		echo "::error::${msg}"
	fi
	status=1
fi

exit "$status"
