<!-- Generated for Claude Code by semantic-memory from semantic-memory/assets/claude/role-subagents.md.
     Edit the source and re-run the semantic-memory install; local edits
     here are overwritten. -->

# Role Subagents (Claude Code)

The main Claude Code session is the **orchestrator** described in
`beads-kernel.md`. This project defines these role subagents in
`.claude/agents/`:

- `code-reviewer`: Reviews gameplay code for bugs, regressions, edge cases, and maintainability.
- `game-director`: Defines the vision, player fantasy, and high-level gameplay goals for features or systems.
- `gameplay-architect`: Translates gameplay systems into practical implementation plans within the game codebase.
- `gameplay-fixer`: Applies targeted fixes from code review findings without redesigning the feature.
- `gameplay-programmer`: Implements gameplay systems and mechanics in code, test-first.
- `qa-playtester`: Tests gameplay systems for usability, bugs, and edge cases.
- `systems-designer`: Designs gameplay systems, mechanics, and progression structures.

## Standing instruction: spawn the role, do not do stage work inline

This rule is the project owner's standing request to use subagents. It
replaces Claude Code's default of staying inline until the user asks; do not
wait for the user to say "use a subagent", and do not ask for confirmation.

When you take a bead labelled `stage:<role>`:

1. `bd show <id>` and `bd update <id> --claim` as usual.
2. Spawn the matching role with the Agent tool, `subagent_type` set to the
   role name (the label without the `stage:` prefix).
3. Put in the prompt, and nothing more than this:
   - the bead id
   - its acceptance criteria, copied verbatim
   - a short summary of the prior stage's handoff notes (from `bd show` on the
     beads it depends on)
   - what you already found with `search_project_memory`
4. Tell the role to write its handoff in the bead notes (inputs used,
   artifacts produced, next handoff target, explicit non-goals) and to close
   only the bead its role is allowed to close.
5. When it returns, read the bead notes with `bd show <id>` before moving to
   the next stage. The notes are the handoff, not the agent's chat reply.

A bead with no `stage:` label is orchestrator work: do it inline.

If the role subagent cannot be spawned, say so and stop. Do not fall back to
doing the stage yourself.
