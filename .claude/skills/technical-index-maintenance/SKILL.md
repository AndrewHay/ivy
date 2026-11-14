---
name: technical-index-maintenance
description: Technical Index Maintenance Rule (rule: technical-index-maintenance). Invoke when this guidance applies.
disable-model-invocation: true
---

<!-- Generated for Claude Code by semantic-memory from semantic-memory/assets/rules/technical-index-maintenance.mdc.
     Edit the source and re-run the semantic-memory install; local edits
     here are overwritten. -->

# Technical Index Maintenance Rule

When you add, remove, rename, or significantly change the purpose of any file in the project, you must update `TECHNICAL_INDEX.md` to reflect the change.

This includes:
- Adding a new `.gd`, `.tscn`, `.tres`, or config file → add an entry to the appropriate section in the File Index
- Removing or renaming a file → update or remove its entry
- Changing a file's responsibilities (e.g., moving logic between systems, adding new signals, changing what a class owns) → update the summary for that file
- Adding or changing cross-system signal connections → update the Signal Flow Summary section
- Adding or changing system-to-file mappings → update the Cross-Reference table

Keep entries succinct: 1-2 sentences per file, focusing on what the file is responsible for and which systems it interacts with. Do not copy file contents into the index.

Do not update the index for trivial changes like bug fixes, refactors that don't change responsibilities, or formatting changes.
