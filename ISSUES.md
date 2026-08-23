# Bug tracking (Beads)

Gameplay bugs are tracked in **bd**, not GitHub Issues.

## Create a bug

```bash
bd create "Fix: camera rig mirror mismatch" \
  --type=bug \
  --priority=1 \
  --acceptance="CamShade is exact mirror of CamSun; qa script confirms"
```

Link to the feature epic when discovered during pipeline work:

```bash
bd dep add <bug-id> <epic-id> --type discovered-from
```

## Verify and close

Only QA (accept stage) closes bug beads after verification:

```bash
bd show <bug-id>
bd close <bug-id> --reason="Verified: run-ui-script scenario + screenshots"
```

See `beads-acceptance.mdc` and `.cursor/agents/qa-playtester.md`.
