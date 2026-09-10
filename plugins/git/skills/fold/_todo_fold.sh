#!/bin/bash
# GIT_SEQUENCE_EDITOR helper for fold.sh: drop the carrier commit's own
# todo line and re-insert it as a fixup directly after the target line,
# so the fold is addressed by SHA instead of autosquash subject
# matching.  Env: GF_TARGET, GF_CARRIER (full SHAs), GF_KIND ("fixup"
# or "fixup -C").
set -euo pipefail

todo=$1
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
found_target=0

while IFS= read -r line; do
	case $line in
	pick\ *)
		sha=${line#pick }
		sha=${sha%% *}
		full=$(git rev-parse --verify --quiet "$sha^{commit}" || echo)
		if [ "$full" = "$GF_CARRIER" ]; then
			continue
		fi
		printf '%s\n' "$line" >>"$tmp"
		if [ "$full" = "$GF_TARGET" ]; then
			printf '%s %s\n' "$GF_KIND" \
				"$(git rev-parse --short "$GF_CARRIER")" >>"$tmp"
			found_target=1
		fi
		;;
	*)
		printf '%s\n' "$line" >>"$tmp"
		;;
	esac
done <"$todo"

if [ "$found_target" != 1 ]; then
	echo "git-fold: target $GF_TARGET not found in rebase todo" >&2
	exit 1
fi
cp "$tmp" "$todo"
