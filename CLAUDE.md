## Maintain scc statistics

On any commit you make, regenerate the `## Code Statistics` section in
`README.md` (the block delimited by `<!-- scc-start -->` and
`<!-- scc-end -->`) with:

    python3 ~/.claude/skills/scc/update_scc.py --here --chart --no-commit

`--chart` is load-bearing. The mermaid pie chart lives INSIDE the marker
block so it is rebuilt from the same numbers as the table below it; a
chart placed above the markers would survive the refresh and silently
go stale. Refresh without the flag and the chart is dropped entirely.
Stage the README together with your other changes so the stats stay in
sync with the code.
