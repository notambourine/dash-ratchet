# shellcheck shell=bash
# The unicode-dash contract: what counts as a dash, and what is held out of the
# rule. Sourced by scripts/check-dashes.sh, so the gate has one definition.
#
# Banned set: U+2010 through U+2015 (hyphen, non-breaking hyphen, figure dash,
# en dash, em dash, horizontal bar), U+2212 minus sign, and the three HTML dash
# entities. Each folds to a plain ASCII hyphen.
#
# Both patterns spell the entities as `&(?:...)`, never the literal form. A
# dash-folding editor rewrites the literal into a bare hyphen, and the pattern
# then matches every hyphen in the repo.
#
# Two engines, one set. perl matches UTF-8 bytes, so invalid encoding anywhere
# in a file can never abort a pass; git grep takes the PCRE form, which reads
# better and is the one to check a new character against.
#
# The PCRE form opens with `(*UTF)`, which is load-bearing. git enables PCRE2
# UTF mode only under a UTF-8 locale, and a container runner sets none, so
# without the verb `\x{2010}` overflows 8-bit mode and git exits 128.
export DASH_BYTES='\xe2\x80[\x90-\x95]|\xe2\x88\x92|&(?:mdash|ndash|minus);'
# shellcheck disable=SC2034  # out-param: read by the sourcing script
DASH_PCRE=(-e '(*UTF)[\x{2010}-\x{2015}\x{2212}]' -e '&(?:mdash|ndash|minus);')

# A line carrying this marker keeps its dash - the gate skips it. For characters
# the code or the copy genuinely needs: a verbatim quote, a real minus sign.
export DASH_MARKER="${DASH_MARKER:-dash-ok}"

# Trees outside the rule, one directory per line of $DASH_EXCLUDE - for bytes not
# yours to edit (captured wire fixtures, append-only migration history).
DASH_EXCLUDE_DIRS=()
if [ -n "${DASH_EXCLUDE:-}" ]; then
	while IFS= read -r _dash_dir; do
		[ -n "$_dash_dir" ] && DASH_EXCLUDE_DIRS+=("$_dash_dir")
	done <<<"$DASH_EXCLUDE"
	unset _dash_dir
fi

# `.` first, never an empty array: bash 3.2 (macOS) errors on "${empty[@]}" under `set -u`.
# shellcheck disable=SC2034  # out-param: read by the sourcing script
DASH_PATHSPEC=(.)
if [ "${#DASH_EXCLUDE_DIRS[@]}" -gt 0 ]; then
	for _dash_dir in "${DASH_EXCLUDE_DIRS[@]}"; do
		DASH_PATHSPEC+=(":(exclude)${_dash_dir}")
	done
	unset _dash_dir
fi
