#!/usr/bin/env bash
# check-msg.sh -- mechanical checks on a commit message.
#
# Encodes the checkable subset of the rules in SKILL.md (kernel
# submitting-patches "canonical patch format", git SubmittingPatches,
# tpp.txt): subject length and shape, blank line after the subject,
# body wrap, imperative mood, no fixup!/amend! left in a final message,
# no transient or tool-generated text, trailers as one block at the end.
#
# Modes (mutually exclusive):
#   --text TEXT          check a message string
#   --file PATH          check a message file (e.g. .git/COMMIT_EDITMSG)
#   --last-commit        check HEAD's message
#   --range A..B         check every non-merge commit in the range
#   --help
#
# Options:
#   --style cc|prefix|any   subject style to require.  Default: auto,
#                           detected from the last 30 non-merge commits
#                           of the current repository (cc = Conventional
#                           Commits "type(scope): ...", prefix = kernel
#                           "subsystem: ...", any = no prefix required)
#
# Exit 0 = clean.  Exit 1 = violations.  Exit 2 = invocation error.
# Each violation is one line:  message:<line>\t<rule> :: <excerpt>
set -uo pipefail

usage() {
	sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
	exit "$1"
}

TMPOUT=$(mktemp)
trap 'rm -f "$TMPOUT"' EXIT

emit() { printf 'message:%s\t%s\n' "$1" "$2" >>"$TMPOUT"; }

# --- subject style -------------------------------------------------------

CC_RE='^[a-z]+(\([^)]+\))?!?: [^ ]'
PREFIX_RE='^[A-Za-z0-9_./-]+(, [A-Za-z0-9_./-]+)*: [^ ]'

detect_style() {
	local subjects n cc pre
	git rev-parse --git-dir >/dev/null 2>&1 || { echo any; return; }
	subjects=$(git log --no-merges --format=%s -30 2>/dev/null)
	n=$(printf '%s\n' "$subjects" | grep -c . || true)
	[ "$n" -ge 5 ] || { echo any; return; }
	cc=$(printf '%s\n' "$subjects" | grep -Ec "$CC_RE" || true)
	pre=$(printf '%s\n' "$subjects" | grep -Ec "$PREFIX_RE" || true)
	if [ $((cc * 10)) -ge $((n * 7)) ]; then echo cc
	elif [ $((pre * 10)) -ge $((n * 7)) ]; then echo prefix
	else echo any
	fi
}

# --- checks --------------------------------------------------------------

check_subject() {	# $1 = subject
	local s=$1 len
	[ -n "$s" ] || { emit 1 "empty subject"; return; }
	len=${#s}
	[ "$len" -le 72 ] || emit 1 "subject is $len chars; keep it under 72 (kernel: 70-75, git: 50 soft) :: $s"
	case "$s" in
	*.) emit 1 "subject ends with a period :: $s" ;;
	esac
	case "$s" in
	fixup!*|squash!*|amend!*)
		emit 1 "fixup!/squash!/amend! subject in a final message; fold it first :: $s" ;;
	esac
	case "$s" in
	'WIP'*|'wip'*|'tmp'*|'temp'*) emit 1 "placeholder subject :: $s" ;;
	esac
	if printf '%s' "$s" | grep -qiE '\b(this (commit|patch|pr|change) (adds|fixes|updates|changes|removes|introduces|makes))'; then
		emit 1 "subject narrates the commit; write what changes, imperative :: $s"
	fi
	# Past tense / -ing at the start of the summary phrase (after any prefix).
	local phrase=${s#*: }
	if printf '%s' "$phrase" | grep -qE '^(Added|Fixed|Updated|Changed|Removed|Improved|Refactored|Implemented|Adding|Fixing|Updating|Removing|Implementing) '; then
		emit 1 "summary phrase is not imperative (\"add\", not \"added\"/\"adding\") :: $s"
	fi
	case $STYLE in
	cc)
		printf '%s' "$s" | grep -qE "$CC_RE" ||
			emit 1 "repository uses Conventional Commits; subject needs \"type(scope): summary\" :: $s"
		;;
	prefix)
		printf '%s' "$s" | grep -qE "$PREFIX_RE" ||
			emit 1 "repository uses subsystem prefixes; subject needs \"area: summary\" :: $s"
		;;
	esac
}

# Git trailers ("Key: value") plus the GitHub closing keywords, which
# have no colon but live in the same footer block.
TRAILER_RE='^([A-Z][A-Za-z-]+: |(Closes|Fixes|Resolves|Refs?|See)(:)? ([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)?#[0-9]+)'
is_trailer() { printf '%s' "$1" | grep -qE "$TRAILER_RE"; }

check_body() {		# reads the message file $1
	local f=$1 n=0 line nlines in_trailers=0 seen_trailer=0 last_nonblank=0 first_body=1
	nlines=$(wc -l <"$f" | tr -d ' ')
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		[ "$n" -gt 1 ] || continue
		if [ "$n" -eq 2 ] && [ -n "$line" ]; then
			emit 2 "no blank line after the subject (autosquash and git log -1 --format=%b both misparse this) :: ${line:0:60}"
		fi
		[ -n "$line" ] && last_nonblank=$n

		# Wrap: skip lines carrying a URL, trailers, and indented lines
		# (code, quoted output, equations).
		if [ ${#line} -gt 75 ] && ! printf '%s' "$line" | grep -qE 'https?://' \
		   && ! is_trailer "$line" && ! printf '%s' "$line" | grep -qE '^[[:space:]]'; then
			emit "$n" "body line is ${#line} chars; wrap at 75 :: ${line:0:60}"
		fi

		# Text that will rot or that belongs to a tool, not the change.
		if printf '%s' "$line" | grep -qE 'claude\.ai/code|Generated (with|by) \[?Claude|🤖'; then
			emit "$n" "session URL / generator signature does not belong in a commit message :: ${line:0:60}"
		fi
		if printf '%s' "$line" | grep -qiE '^Co-Authored-By:'; then
			emit "$n" "no Co-Authored-By trailer :: ${line:0:60}"
		fi
		if printf '%s' "$line" | grep -qiE '\bthis (commit|patch|pr|pull request) (adds|fixes|updates|changes|removes|introduces|makes|is)\b'; then
			emit "$n" "\"this commit does ...\" -- the reader knows it is a commit; describe the change directly (tpp 4c) :: ${line:0:60}"
		fi
		if printf '%s' "$line" | grep -qiE '\b(in (this|the) series|in (a|the) (later|next|following|subsequent) (patch|commit|pr)|previous (version|iteration|review)|as (discussed|requested) (in|by))\b'; then
			emit "$n" "not self-contained: references a series, a later commit or an earlier round (tpp 4d) :: ${line:0:60}"
		fi
		if printf '%s' "$line" | grep -qE '^Fixes: [0-9a-f]{7,40}( |$)' && ! printf '%s' "$line" | grep -qE '^Fixes: [0-9a-f]{12,40} \(".+"\)$'; then
			emit "$n" "Fixes: needs >= 12 hex digits and the (\"subject\") of the commit :: ${line:0:60}"
		fi

		# Trailers: once the trailer block starts, only trailers and
		# blank lines may follow.
		if is_trailer "$line" && [ "$n" -gt 2 ]; then
			seen_trailer=$n
			in_trailers=1
		elif [ -n "$line" ] && [ "$in_trailers" = 1 ] && ! printf '%s' "$line" | grep -qE '^[[:space:]]'; then
			emit "$n" "prose after trailer block (trailer at line $seen_trailer); trailers go last :: ${line:0:60}"
			in_trailers=0
		fi
	done <"$f"
}

check_message_file() {	# $1 = file
	local f=$1 subject
	subject=$(head -1 -- "$f")
	check_subject "$subject"
	check_body "$f"
}

# --- main ----------------------------------------------------------------

mode=
STYLE=auto
args=()
while [ $# -gt 0 ]; do
	case "$1" in
	--text|--file|--last-commit|--range|--help)
		mode=$1; shift ;;
	--style)
		[ $# -ge 2 ] || usage 2
		STYLE=$2; shift 2 ;;
	*)
		args+=("$1"); shift ;;
	esac
done
[ "$mode" = --help ] && usage 0
[ -z "$mode" ] && usage 2
case $STYLE in auto) STYLE=$(detect_style) ;; cc|prefix|any) ;; *) usage 2 ;; esac

tmp=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$tmp' '$TMPOUT'" EXIT

case "$mode" in
--text)
	printf '%s\n' "${args[0]:-}" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp"
	check_message_file "$tmp"
	;;
--file)
	f=${args[0]:-}
	[ -f "$f" ] || { echo "[check-msg] no such file: $f" >&2; exit 2; }
	grep -v '^#' -- "$f" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp"
	check_message_file "$tmp"
	;;
--last-commit)
	git rev-parse --git-dir >/dev/null 2>&1 || { echo "[check-msg] not in a git repo" >&2; exit 2; }
	git log -1 --format=%B | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp"
	check_message_file "$tmp"
	;;
--range)
	git rev-parse --git-dir >/dev/null 2>&1 || { echo "[check-msg] not in a git repo" >&2; exit 2; }
	range=${args[0]:-}
	[ -n "$range" ] || usage 2
	bad=0
	for c in $(git rev-list --no-merges --reverse "$range"); do
		: >"$TMPOUT"
		git log -1 --format=%B "$c" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp"
		check_message_file "$tmp"
		if [ -s "$TMPOUT" ]; then
			bad=$((bad + 1))
			echo "== $(git log -1 --format='%h %s' "$c")"
			cat "$TMPOUT"
		fi
	done
	if [ "$bad" -gt 0 ]; then
		echo "[check-msg] $bad commit(s) with violations in $range." >&2
		exit 1
	fi
	echo "[check-msg] no violations in $range." >&2
	exit 0
	;;
esac

n=$(wc -l <"$TMPOUT" | tr -d ' ')
if [ "$n" -gt 0 ]; then
	cat "$TMPOUT"
	echo "[check-msg] $n violation(s) (style: $STYLE)." >&2
	exit 1
fi
echo "[check-msg] no violations (style: $STYLE)." >&2
exit 0
