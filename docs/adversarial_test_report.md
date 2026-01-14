# Adversarial Testing Report

To verify the robustness of the `zemacs` core, we implemented a fuzzing-based adversarial test suite `src/core/test_adversarial.zig`.

## Methodology

### 1. Gap Buffer vs Reference
We compared the `GapBuffer` implementation against a simple `ReferenceBuffer` (wrapping `std.ArrayList`).
- **Iterations**: 5,000 random operations.
- **Operations**: Random mix of Insertions (60%) and Deletions (40%).
- **Inputs**: Random variations of position, length, and content.
- **Invariant**: `GapBuffer.toOwnedSlice() == ReferenceBuffer.data`.

### 2. Undo/Redo Cycles
We verified `UndoManager` by maintaining a linear history of expected states.
- **Iterations**: 1,000 random operations.
- **Operations**:
  - New Edits (truncates redo history).
  - Undo (steps back in history).
  - Redo (steps forward in history).
- **Invariant**: `Buffer state == Expected state from History`.

## Results

```
All 5 tests passed.
```

The tests confirm that:
1. The Gap Buffer logic handles gap movement, resizing, and arbitrary edits correctly without data corruption.
2. The Undo/Redo logic correctly restores previous buffer states, including complex cycle scenarios.

This provides high confidence in the correctness of the core data structures.
