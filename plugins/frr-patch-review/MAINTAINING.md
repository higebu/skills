# Maintaining frr-patch-review

The empirical half of `agents/frr-reviewer.md` (the defect patterns and
the false-positive guide) comes from public review comments on
`FRRouting/frr` pull requests. To refresh it, pull the latest comments:

```sh
for p in $(seq 1 70); do
  gh api "repos/FRRouting/frr/pulls/comments?sort=created&direction=desc&per_page=100&page=$p" \
    --jq '.[] | {id,rid:.in_reply_to_id,u:.user.login,path,body,at:.created_at}'
done > frr_comments.jsonl
```

Then rebuild the checklist and the false-positive guide from it, and
update the provenance numbers in the agent.
