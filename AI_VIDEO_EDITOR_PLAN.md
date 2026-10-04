# AI Video Editor — Current Prototype Plan

## Project Rule

Build this **one capability at a time**.

If a method fails, **change the method — do not drop the requirement**.

Do not move to the next part until the current part is explicitly confirmed finished.

---

# PART 1 — EDITOR FOUNDATION

**STATUS: IN PROGRESS**

## Goal

Build the smallest real working foundation:

`create project → import real media → place on timeline → trim → render → validate`

This part proves that the editor backend can actually manipulate media and produce a valid video.

## Architecture

`Python Editor Backend → Shotcut / MLT → Project Timeline → Rendered MP4 → Validation`

The implementation must inspect the environment first and determine the most reliable programmatic way to control the intended editor/rendering stack.

Do **not** assume Shotcut has a conventional API.

If Shotcut's GUI is mainly a frontend while MLT is the reliable programmatic rendering/project layer, use MLT underneath while keeping Shotcut/MLT as the intended editor technology.

Do not silently replace the editor with an unrelated system.

## Suggested Structure

```
editor/
├── project/
├── media/
├── timeline/
├── render/
├── validation/
└── tests/
```

The exact structure may differ if the implementation has a better reason, but responsibilities must remain separated.

---

## Required Operations

### 1. `create_project`

Must support:
- project ID
- width
- height
- FPS
- duration
- tracks
- clips

Use sensible defaults such as 1920×1080 and 30 FPS unless the implementation requires otherwise.

### 2. `import_video`

Must:
- verify the file exists
- reject missing/invalid media
- preserve the original
- store enough metadata/reference information for later timeline operations

### 3. `add_clip`

Must support:
- clip ID
- source file
- source in
- source out
- timeline start
- duration
- track

### 4. `trim_clip`

Must:
- modify the usable source range
- reject invalid ranges
- update the deterministic project state

### 5. `render`

Must:
- use the actual editor/rendering system
- render a real MP4
- report useful failures

### 6. `validate_render`

Do **not** treat a successful process exit code as proof of success.

Validation must check that:
- output exists
- output is non-empty
- output is parseable/playable
- duration is sensible
- dimensions are correct/sensible
- FPS is correct/sensible

Use ffprobe or an equivalent real media inspection tool when available.

---

# Canonical Project State

The project state must be deterministic and inspectable, preferably JSON.

Example:

```json
{
  "project_id": "test_project",
  "width": 1920,
  "height": 1080,
  "fps": 30,
  "duration": 9.0,
  "tracks": [
    {
      "id": "video_1",
      "type": "video",
      "clips": [
        {
          "id": "clip_1",
          "source": "input.mp4",
          "source_in": 1.0,
          "source_out": 10.0,
          "timeline_start": 0.0,
          "duration": 9.0
        }
      ]
    }
  ]
}
```

The exact schema can differ.

The important requirements are:
- deterministic
- inspectable
- serializable
- represents actual editor state
- not merely AI memory

---

# Mandatory End-to-End Test

Use a **real video file**.

Test exactly this flow:

1. Create project.
2. Import approximately 10 seconds of video.
3. Add it to the timeline.
4. Remove/trim the first 1 second.
5. Render.
6. Validate the rendered file.
7. Inspect the final duration.

Expected result:

Approximately **9 seconds**, within a reasonable tolerance.

No mocks.

No fake video.

No fake renderer.

No "the command exited 0, therefore it worked."

The test must prove that the actual media went through the actual editing/rendering pipeline.

---

# Required Error Tests

Test useful failures for:

- missing input file
- unsupported/corrupt media
- invalid timeline position
- invalid trim range
- duplicate clip ID
- render failure
- corrupt render output
- missing renderer dependency

Errors should clearly explain what failed and, where possible, how to diagnose it.

---

# Original Media Safety

The original input media must never be modified.

Work from references/copies as appropriate.

Ideally verify that the original file is byte-for-byte unchanged after the test.

---

# Reproducibility

The same:

`project state + media`

must produce the same logical timeline.

Avoid hidden global state.

Keep useful logs so failures can be reproduced and diagnosed.

---

# Testing Philosophy

A test is not successful merely because:
- a function returned successfully
- a command exited with code 0
- an output file exists

The actual rendered media must be inspected and shown to be valid.

---

# STRICT PART 1 SCOPE

Do **NOT** implement yet:

- LLM integration
- MCP server
- AI tool calling
- computer vision
- video understanding
- self-review
- self-correction
- fine-tuning
- datasets
- asset recommendation
- Minecraft automation
- GUI
- cloud deployment
- multi-agent systems

Those come later.

---

# Part 1 Deliverable Report

When Part 1 is complete, report:

1. Files/modules created.
2. How the backend controls Shotcut/MLT.
3. Dependencies required.
4. Exact test instructions.
5. Exact end-to-end test performed.
6. Input duration.
7. Output duration.
8. Render validation results.
9. Confirmation that the original input remained unchanged.
10. Limitations or parts requiring another approach.

---

# PART 1 STOP CONDITION

Once this works reliably:

`create → import → timeline → trim → render → validate`

with real media:

**STOP.**

Do not start AI/MCP/self-correction work until Part 1 has been explicitly confirmed finished.

---

# PART 2 — NOT STARTED

Only after Part 1 is confirmed:

Connect the main AI model to the real editor through a structured tool/API interface.

The **same main model** will eventually:
- make the editor tool calls
- render what it created
- watch/inspect the rendered result
- compare intended vs actual
- decide corrections

There is no separate AI observer in the core editing loop.

---

# FUTURE: JOURNAL / ACCOUNTABILITY SYSTEM

The `journal.json` design is reserved for the later AI editing/self-correction stage.

Each edit will eventually have:

1. `Intended`
2. `Visual_intended`
3. `result`
4. `Mistakes`
5. `Fixes`
6. `human_feedback`
7. `fix_edit_id`

Fix IDs use:

`<edit_id>-fix-<number>`

Example:

`42ab3 → 42ab3-fix-1 → 42ab3-fix-2 → 42ab3-fix-3`

Once committed, a journal entry is immutable.

The model cannot rewrite its own previous history. If it discovers that an earlier assessment was wrong, it creates a new linked record explaining the discrepancy.

This is **not part of Part 1**.

---

# Core Project Philosophy

**If something doesn't work, change the method — don't drop the capability.**

The requirement stays.

The implementation can change.
