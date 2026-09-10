#!/bin/bash
# fold.sh -- fold a staged diff (fixup) or a rewritten commit message
# (amend) into a target commit, addressing the target by SHA via direct
# rebase-todo editing.  Never creates subject-matched fixup!/amend!
# commits, so the two silent autosquash failure modes (malformed amend!
# subject, duplicate target subjects) cannot occur.  Verifies the
# result afterwards.  See SKILL.md.
#
# usage: fold.sh fixup <target-sha>             fold staged diff into target
#        fold.sh amend <target-sha> <msg-file>  replace target's full message
#        fold.sh all <base-ref>                 autosquash floating fixup!/amend!
#        fold.sh check <base-ref>               post-rebase verification only
#
# Environment:
#   GIT_FOLD_MSG_CHECK   command run on a rewritten message (amend mode)
#                        and on the folded target's message; receives the
#                        text as "--text <msg>".  Default: the
#                        commit-message skill's check-msg.sh next to this
#                        skill.  Set to an empty string to disable.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MSG_CHECK=${GIT_FOLD_MSG_CHECK-"$SCRIPT_DIR/../commit-message/check-msg.sh"}

die()  { printf 'git-fold: error: %b\n' "$*" >&2; exit 1; }
warn() { printf 'git-fold: WARNING: %b\n' "$*" >&2; }

usage() { sed -n '9,12p' "$0" | sed 's/^# \?//' >&2; exit 2; }

msg_check_applies() { [ -n "$MSG_CHECK" ] && [ -x "$MSG_CHECK" ]; }

require_clean() {
	git diff --quiet || die "unstaged changes present; stage or stash them first"
}

check_floating() {	# $1 = base
	local bad
	bad=$(git log --format='%h %s' "$1"..HEAD |
		grep -E '^[0-9a-f]+ (fixup|squash|amend)! ' || true)
	[ -z "$bad" ] || die "fixup!/amend! commits still floating after fold:\n$bad"
}

check_pure_renames() {	# $1 = base
	local c ns
	for c in $(git rev-list --no-merges "$1"..HEAD); do
		ns=$(git show --format= --name-status "$c")
		[ -n "$ns" ] || continue
		if ! printf '%s\n' "$ns" | grep -qv $'^R100\t'; then
			warn "$(git log -1 --format='%h %s' "$c") is a pure rename -- verify no content change was lost (edit-then-git-mv trap)"
		fi
	done
}

post_checks() {		# $1 = base
	check_floating "$1"
	check_pure_renames "$1"
}

# Fold $carrier into $target via a rebase whose todo we edit directly.
# $1 = todo action ("fixup" or "fixup -C").  On conflict: abort the
# rebase, drop the carrier, and leave its diff staged again.
run_fold() {
	if ! GF_TARGET=$target GF_CARRIER=$carrier GF_KIND="$1" \
	     GIT_SEQUENCE_EDITOR="$SCRIPT_DIR/_todo_fold.sh" \
	     git rebase --quiet -i "$base"; then
		git rebase --abort 2>/dev/null || true
		git reset --quiet --soft HEAD^
		die "rebase failed; branch restored to pre-fold state (your change is staged again)"
	fi
}

report() {		# $1 = new target sha
	echo "== folded: $(git log -1 --format='%h %s' "$1") =="
	echo "== tree diff (old tip $old_tip_short -> new tip $(git rev-parse --short HEAD)) =="
	git diff --stat "$old_tip" HEAD
	if msg_check_applies; then
		"$MSG_CHECK" --text "$(git log -1 --format=%B "$1")" || true
	fi
	post_checks "$base"
}

[ $# -ge 1 ] || usage
mode=$1; shift
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git worktree"

case $mode in
fixup)
	[ $# -eq 1 ] || usage
	target=$(git rev-parse --verify "$1^{commit}") || die "bad target ref: $1"
	if git diff --cached --quiet; then
		die "nothing staged"
	fi
	require_clean
	old_tip=$(git rev-parse HEAD)
	old_tip_short=$(git rev-parse --short HEAD)
	base=$(git rev-parse --verify --quiet "$target^") || die "target is a root commit; folding into it is not supported"
	n_above=$(git rev-list --count "$target"..HEAD)
	staged_pid=$(git diff --cached | git patch-id --stable | cut -d' ' -f1)
	git commit --quiet --no-verify -m "git-fold carrier (discarded on fold)"
	carrier=$(git rev-parse HEAD)
	run_fold fixup
	new_target=$(git rev-parse "HEAD~$n_above")
	folded_pid=$(git diff "$old_tip" HEAD | git patch-id --stable | cut -d' ' -f1)
	[ "$staged_pid" = "$folded_pid" ] ||
		die "tree diff after fold differs from the staged diff -- inspect git diff $old_tip HEAD"
	report "$new_target"
	;;

amend)
	[ $# -eq 2 ] || usage
	target=$(git rev-parse --verify "$1^{commit}") || die "bad target ref: $1"
	msgfile=$2
	[ -s "$msgfile" ] || die "message file empty or missing: $msgfile"
	case $(head -1 "$msgfile") in
	fixup!*|amend!*|squash!*)
		die "message file must hold the final message; drop the fixup!/amend! prefix line" ;;
	esac
	git diff --cached --quiet || die "staged changes present; amend replaces only the message"
	require_clean
	old_tip=$(git rev-parse HEAD)
	old_tip_short=$(git rev-parse --short HEAD)
	base=$(git rev-parse --verify --quiet "$target^") || die "target is a root commit; folding into it is not supported"
	n_above=$(git rev-list --count "$target"..HEAD)
	if msg_check_applies; then
		"$MSG_CHECK" --text "$(cat "$msgfile")" || die "message fails $MSG_CHECK; fix it before folding"
	fi
	git commit --quiet --no-verify --allow-empty -F "$msgfile"
	carrier=$(git rev-parse HEAD)
	run_fold "fixup -C"
	new_target=$(git rev-parse "HEAD~$n_above")
	git diff --quiet "$old_tip" HEAD ||
		die "tree changed during a message-only amend -- inspect git diff $old_tip HEAD"
	report "$new_target"
	;;

all)
	[ $# -eq 1 ] || usage
	base=$(git rev-parse --verify "$1^{commit}") || die "bad base ref: $1"
	require_clean
	old_tip=$(git rev-parse HEAD)
	# autosquash matches by subject; refuse when any floating commit's
	# referenced subject prefixes more than one candidate in range.
	subjects=$(git log --format='%s' "$base"..HEAD |
		{ grep -E '^(fixup|squash|amend)! ' || true; } |
		sed -E 's/^(fixup|squash|amend)! //' | sort -u)
	[ -n "$subjects" ] || die "no floating fixup!/amend! commits in $1..HEAD"
	while IFS= read -r subj; do
		n=$(git log --format='%s' "$base"..HEAD |
			{ grep -Ev '^(fixup|squash|amend)! ' || true; } |
			awk -v s="$subj" 'index($0, s) == 1' | wc -l)
		[ "$n" -eq 1 ] ||
			die "subject \"$subj\" matches $n commits in range; fold it explicitly with fold.sh fixup/amend"
	done <<<"$subjects"
	if ! GIT_SEQUENCE_EDITOR=: git rebase --quiet -i --autosquash "$base"; then
		git rebase --abort 2>/dev/null || true
		die "autosquash rebase failed; branch restored"
	fi
	echo "== tree diff (old tip -> new tip) =="
	git diff --stat "$old_tip" HEAD
	post_checks "$base"
	echo "git-fold: all floating fixups folded."
	;;

check)
	[ $# -eq 1 ] || usage
	base=$(git rev-parse --verify "$1^{commit}") || die "bad base ref: $1"
	post_checks "$base"
	echo "git-fold: no floating fixup!/amend! in $1..HEAD."
	;;

*)
	usage
	;;
esac
