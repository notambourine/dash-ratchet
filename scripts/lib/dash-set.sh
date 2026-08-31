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

# Banned too: the per-line opt-out marker. The class around `o` keeps this file
# from matching itself, and the short spelling is a substring of the longer ones.
export DASH_MARKER_BYTES='dash-[o]k'

# Held out by default: a package manager's, an agent's, or an upstream author's
# bytes - nothing a consumer reads and nothing anyone retypes by hand.
_dash_defaults=(
	'**/node_modules/**'
	'**/vendor/**'
	'**/.claude/**'
	'**/.cursor/**'
	'**/*.lock'
	'**/package-lock.json'
	'**/npm-shrinkwrap.json'
	'**/pnpm-lock.yaml'
	'**/bun.lockb'
	'**/go.sum'
	'**/CHANGELOG.md'
	'**/LICENSE*'
	'**/CLAUDE.md'
	'**/AGENTS.md'
)

# Trees outside the rule, one pathspec per line of $DASH_EXCLUDE - for bytes not
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
# glob magic: `**/name` hits every depth including the root, and a directory
# needs the trailing `/**` - the bare prefix matches the dir, not its files.
case "${DASH_EXCLUDE_DEFAULTS:-true}" in
true)
	for _dash_pat in "${_dash_defaults[@]}"; do
		DASH_PATHSPEC+=(":(exclude,glob)${_dash_pat}")
	done
	unset _dash_pat
	;;
false) ;;
*)
	echo "DASH_EXCLUDE_DEFAULTS takes true or false, not '${DASH_EXCLUDE_DEFAULTS}'" >&2
	exit 1
	;;
esac
unset _dash_defaults
if [ "${#DASH_EXCLUDE_DIRS[@]}" -gt 0 ]; then
	for _dash_dir in "${DASH_EXCLUDE_DIRS[@]}"; do
		DASH_PATHSPEC+=(":(exclude)${_dash_dir}")
	done
	unset _dash_dir
fi
