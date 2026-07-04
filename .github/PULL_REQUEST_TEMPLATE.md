## What & why

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] If a `SKILL.md` changed: bumped its `version` in frontmatter
- [ ] If a generated script changed: re-ran it against `examples/demo-webapp/` and committed the refreshed snapshot (no hand-edited generated sections)
- [ ] Embedded bash passes `bash -n`; no `rm` anywhere (use `trash`)
- [ ] Re-running the skill on an already-initialized project still only touches sentinel-managed blocks
