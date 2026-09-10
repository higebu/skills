#!/bin/bash
# safe-push.sh -- push the current branch with the lease pinned to the
# real remote tip (never a possibly-gone tracking ref).  Before any
# non-fast-forward push it enforces: no floating fixup!/amend! commits,
# and the review-branch gate for large rewrites; it can archive-tag the
# old remote tip first.  See SKILL.md.
#
# usage: safe-push.sh [--remote <name>] [--approved] [--archive <reason>]
#
#   --remote <name>    remote to push to (default: origin)
#   --approved         push a rewrite whose old->new tree diff exceeds
#                      GIT_SAFE_PUSH_REVIEW_THRESHOLD (default 200 lines);
#                      only after the user reviewed it on <branch>-rework
#   --archive <reason> tag the old remote tip archive/<branch>/<date>-<reason>
#                      and push the tag before the branch, so a SHA someone
#                      cited stays reachable after the rewrite
set -euo pipefail

die()  { printf 'git-safe-push: error: %b\n' "$*" >&2; exit 1; }
usage() { sed -n '8,17p' "$0" | sed 's/^# \?//' >&2; exit 2; }

remote=origin
approved=0
archive=""
while [ $# -gt 0 ]; do
	case $1 in
	--approved) approved=1 ;;
	--archive)
		[ $# -ge 2 ] || usage
		archive=$2; shift ;;
	--remote)
		[ $# -ge 2 ] || usage
		remote=$2; shift ;;
	-h|--help) usage ;;
	*) die "unknown argument: $1" ;;
	esac
	shift
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git worktree"
branch=$(git symbolic-ref --quiet --short HEAD) || die "detached HEAD"
head=$(git rev-parse HEAD)

remote_line=$(git ls-remote "$remote" "refs/heads/$branch")
if [ -z "$remote_line" ]; then
	echo "git-safe-push: $remote/$branch does not exist yet; plain push."
	git push -u "$remote" "$branch"
	exit 0
fi
expected=${remote_line%%$'\t'*}

if [ "$expected" = "$head" ]; then
	echo "git-safe-push: $remote/$branch already at $(git rev-parse --short "$head"); nothing to push."
	exit 0
fi
git cat-file -e "$expected" 2>/dev/null ||
	die "remote tip $expected is not present locally -- git fetch $remote first"

mb=$(git merge-base "$expected" "$head")
floating=$(git log --format='%h %s' "$mb"..HEAD |
	{ grep -E '^[0-9a-f]+ (fixup|squash|amend)! ' || true; })
[ -z "$floating" ] ||
	die "floating fixup!/amend! commits present -- fold them first (fold.sh):\n$floating"

if git merge-base --is-ancestor "$expected" "$head"; then
	git push "$remote" "$branch"
	exit 0
fi

# --- non-fast-forward: the push rewrites $remote/$branch ---

lines=$(git diff --shortstat "$expected" "$head" |
	{ grep -oE '[0-9]+ (insertion|deletion)' || true; } |
	awk '{s+=$1} END {print s+0}')
thr=${GIT_SAFE_PUSH_REVIEW_THRESHOLD:-200}
if [ "$lines" -gt "$thr" ] && [ "$approved" != 1 ]; then
	die "old->new tree diff is $lines lines (> $thr): push to $branch-rework and get user approval first, then re-run with --approved"
fi

if [ -n "$archive" ]; then
	tag="archive/$branch/$(date +%F)-$archive"
	git tag "$tag" "$expected"
	git push "$remote" "$tag"
	echo "git-safe-push: archived old tip as $tag"
fi

git push --force-with-lease="refs/heads/$branch:$expected" \
	"$remote" "HEAD:refs/heads/$branch"
echo "git-safe-push: $remote/$branch: $(git rev-parse --short "$expected") -> $(git rev-parse --short "$head") (tree diff: $lines lines)"
