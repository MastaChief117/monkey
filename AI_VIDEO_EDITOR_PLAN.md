# AI Video Editor — Implementation Plan

## Current Status

### Part 1 — Editor Foundation
**STATUS: IN PROGRESS**

Goal: `create project → import real media → timeline → trim → render → validate`

Requirements:
- Real editor/rendering backend.
- Deterministic, inspectable project state.
- Real media only; no fake renderer or mocked end-to-end test.
- Import video without modifying the original.
- Add clips with source in/out, timeline position, duration, and track.
- Trim clips with validation.
- Render to a real MP4.
- Validate the rendered file using actual media inspection (for example ffprobe/equivalent).
- Test missing/corrupt media, invalid timeline/trim ranges, duplicate IDs, render failures, corrupt output, and missing renderer dependencies.
- Stop Part 1 once the complete real-media path works.

**Do not add yet:** AI, MCP, self-review, self-correction, training, datasets, asset recommendation, Minecraft automation, GUI, cloud deployment, or multi-agent systems.

---

## Part 2 — AI/Editor Control

After Part 1 is explicitly confirmed finished:
- Define the editor tool/API surface.
- Connect the main multimodal model to the editor through MCP/tool calls.
- The main model itself makes the editing calls.
- Preserve deterministic project state outside the model.
- Do not make a separate AI observer the core editing loop.

---

## Part 3 — Render → Watch → Compare

Build the closed-loop editing process:
`INTENT → EDIT → RENDER → MAIN MODEL WATCHES RESULT → COMPARE → CORRECT`

Target local editing chunk:
- ~8 seconds.
- ~3 seconds of preceding rendered context for continuity.
- Start with a practical observation/frame-sampling strategy and increase it when needed.

The main model must directly inspect what it made and compare the actual render against its intended result.

---

## Part 4 — Journal / Accountability System

### `journal.json`

Add an immutable edit-history record for every edit/chunk.

Each edit record contains exactly these seven core parameters:

1. `Intended` — what the model intended to do.
2. `Visual_intended` — what the model expected the result to look like.
3. `result` — what actually came out, based on observation of the rendered result.
4. `Mistakes` — what went wrong.
5. `Fixes` — what should be changed.
6. `human_feedback` — human guidance when the model's attempted fix is wrong or it genuinely cannot resolve the issue.
7. `fix_edit_id` — linked fix ID using the format `<edit_id>-fix-<number>`.

Example chain:
`42ab3 → 42ab3-fix-1 → 42ab3-fix-2 → 42ab3-fix-3`

### Immutability rule

Once an edit record is committed, the model **cannot rewrite, delete, or retroactively alter its own previous record**.

If the model later discovers that an earlier assessment was wrong, it must create a new linked entry explaining the correction/discrepancy.

The journal is an accountability/history record, not model memory that can be rewritten after the fact.

### Observation rule

`result` must represent observed reality, not what the model assumes happened.

Deterministic editor/media facts can support the observation, but the same main model must be able to inspect the rendered result and interpret it.

### Human escalation

Human feedback is an escalation path, not the normal editing mechanism. The system should first attempt to diagnose and fix its own mistakes.

---

## Part 5 — Whole-Video Review

After local chunks are accepted:
- Review the complete rendered video.
- Compare the whole result against the script and intended style.
- Identify continuity, pacing, timing, audio, visual, and structural problems.
- Apply final corrections through the same editor/model loop.
- Preserve those corrections in the journal.

---

## Part 6 — Style / Reference Editing

Use a curated reference set to teach the system **what/when** editing decisions should look like.

- Final reference set: 25 videos selected from a larger shortlist.
- References teach pacing, cut rhythm, captions, zooms, SFX, transitions, music behavior, holds, reactions, and editing personality.
- Do not treat references as literal content to copy.

---

## Part 7 — Training

Only after the real editing loop works:
- Build training data from editor tool usage, real editing runs, observations, mistakes, and corrections.
- Use efficient fine-tuning/PEFT where practical.
- Keep training behavior separate from persistent project state.
- Successful and failed runs can become future training examples, with curation/filtering to avoid amplifying mistakes.

---

## Core Rules

1. **The model must see what it made.**
2. The same main model performs the editing calls and observes the rendered result.
3. Never assume a first-pass edit is correct.
4. Use actual editor state, not guessed state.
5. Use rendered output as evidence.
6. Never mutate original source assets.
7. Keep a rich editor/project representation rather than reducing everything to raw FFmpeg commands.
8. MCP/API first; GUI only as fallback/debug where necessary.
9. Separate intention, observation, inference, and decision.
10. Checkpoint important state.
11. If an implementation method fails, **change the method — do not drop the capability/requirement**.
12. Ask the human for help only when the system genuinely cannot resolve the problem.

---

## Current Rule

**Do not advance to the next part until the current part is explicitly confirmed finished.**
