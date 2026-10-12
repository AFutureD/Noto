---
name: port-tinycast-notes
description: Sync the Notes feature from Tinycast into Noto, up to Tinycast's latest release tag. Lays out the upstream changes and whether each ports without conflict, then waits for confirmation before changing anything.
argument-hint: "[tag-or-commit]"
disable-model-invocation: true
---

Sync the Notes-related changes from Tinycast (`${CLAUDE_PROJECT_DIR}/../tinycast`) into Noto.

Scope: only the difference between the last ported commit, recorded in the `Last ported commit`
row of `docs/development.md`, and `$0`, which defaults to Tinycast's latest release tag. Only
changes that concern the Notes feature.

Before any change to the project:

1. Lay out what changed upstream, commit by commit, in terms of behaviour and the Noto files it
   touches.
2. For each commit, say whether it ports without conflict, needs adaptation to Noto's own types, or
   should not be ported because it serves a Tinycast feature Noto does not have. A change to
   Tinycast's Markdown parser, styler, renderer or text view is never ported: Noto's editor is
   MDTextKit (`docs/features/notes.md#editor`).
3. Wait for confirmation.

After confirmation, port the accepted commits in upstream order, one Noto commit per upstream
commit, with Noto's docs kept true in ASD-STE100 wording, the `Last ported commit` row moved, and
the definition of done in `docs/testing.md` met for each.
