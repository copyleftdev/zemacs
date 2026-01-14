# Emacs Functionality Analysis

This document outlines "clever" functionality found in GNU Emacs `src/` that can be harnessed to enhance `zemacs`.

## 1. The Gap Buffer (`src/buffer.h`, `src/insdel.c`)

### Concept
Emacs uses a **Gap Buffer** to store text. Instead of a simple array or a rope, it uses a flat array with a "gap" of unused memory in the middle.
- **Structure**: `[ Text Before Gap | ... GAP ... | Text After Gap ]`
- **Insertion**: Text is inserted into the gap. If the gap is full, the buffer is reallocated.
- **Movement**: The gap is moved to the point of insertion/deletion. Moving the gap involves `memmove` of the text between the old and new key positions.

### Why it's clever
- **Locality of Reference**: Edits typically happen in clusters. Moving the gap once allows for many subsequent fast insertions without allocation or copying.
- **Simplicity**: Converting to a C string (for regex search or system calls) is trivial (two `memcpy`s or direct access if the gap is at the end).
- **Zig Implementation**: Zig's slices and manual memory management are perfect for implementing a high-performance gap buffer.

### Harnessing in Zemacs
Currently, `zemacs` appears to process files as strings or via external tools. Implementing a `GapBuffer` struct in Zig would allow `zemacs` to:
- Perform efficient in-memory editing before saving.
- Handle large files with responsive insertion/deletion.
- Serve as a foundation for a true editor backend.

## 2. Markers (`src/buffer.h`)

### Concept
**Markers** are pointers to positions in the text that *move automatically* when text is inserted or deleted.
- **Mechanism**: Markers are stored in a linked list attached to the buffer.
- **Update**: When `insdel.c` modifies the buffer, it iterates through the markers and adjusts their offsets:
  - If text is inserted *before* a marker, the marker increments.
  - If text is deleted *containing* a marker, the marker moves to the start of the deletion.

### Why it's clever
- **Semantic Stability**: Allows keeping references to "Function Start" or "Error Line" valid even as the user (or agent) edits the file above them.
- **LSP Integration**: Helps coordinate between asynchronous LSP responses (which refer to a version of the document) and the current state.

### Harnessing in Zemacs
`zemacs`'s LSP tools (`lsp.zig`) use static line/col. If the agent edits the file, these coordinates become stale. Implementing Markers would allow `zemacs` to track entities robustly.

## 3. The Undo List (`src/undo.c`)

### Concept
Emacs does not use a "Command pattern" stack for undo. It uses a **Linear Undo List** of primitives.
- **Data Structure**: A simple list of cons cells.
- **Entries**:
  - Insert: `(beg . end)` (tells undo to delete this range).
  - Delete: `(string . beg)` (tells undo to re-insert `string` at `beg`).
  - Marker: `(marker . adjustment)`.
- **Usage**: To "Undo", Emacs iterates the list, executing the inverse actions, and *recording* them as new undo records (so you can "undo the undo").

### Why it's clever
- **Infinite Undo/Redo**: No separate "redo" stack. Redo is just undoing an undo.
- **Granularity**: Can handle arbitrary changes, not just "commands".
- **Efficiency**: Only stores the delta.

### Harnessing in Zemacs
For an AI agent, **Safety** is paramount. Implementing an Undo Ring allows `zemacs` to:
- Revert agent actions granularly.
- "Try" edits and rollback if they break tests.
- Provide a safety net for the user.

## 4. Key Sequence Translation (`src/keyboard.c`)

### Concept
Emacs allows mapping arbitrary sequences of input events to commands using **Keymaps**.
- **heirarchy**: Global map -> Major Mode map -> Minor Mode lists.
- **Prefix Keys**: Keys can be bound to another keymap (e.g., `C-x`).

### Harnessing in Zemacs
If `zemacs` intends to wrap `repl` or `ui` interactions, a hierarchical input system allows for complex modal interactions (like Vim or Emacs) defined capabilities.

## Recommendation
Start by implementing **GapBuffer** and **UndoList** in Zig. These provide the core state management that distinguishes a "text editor" from a "text processor".
