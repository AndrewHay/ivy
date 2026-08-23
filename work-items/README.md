# Work items (archived)

**New work is tracked in bd**, not this file. **Migration complete (2026-08-22):** all 33
non-`done` rows in `WORK_ITEMS.md` (`open`, `partial`, `needs re-decision`, `deferred`) were
migrated into bd as 33 issues under 5 milestone beads (M2.5, M2.6, M2.7, M3, M4) plus one
cross-cutting tech-debt epic. `WORK_ITEMS.md`'s own `## Queue` header carries the full WI → bd
ID mapping table.

- Run `bd ready` for the queue
- See [BEADS-MIGRATION.md](https://github.com/AndrewHay/semantic-memory/blob/main/docs/BEADS-MIGRATION.md) for epic + pipeline bead shape
- Rules: `beads-kernel.mdc`, `beads-acceptance.mdc`, `agent-pipeline.mdc`

## Archive

- **`WORK_ITEMS.md`** — historical queue and phase narrative, now fully archived. Do not add new
  W- rows here, and do not resurrect its `Status` column as a source of truth — the mapping
  table points at the live bd issue for anything that was still open at migration time.

All open queue rows have been migrated to bd; `WORK_ITEMS.md` is read-only history from here on.
