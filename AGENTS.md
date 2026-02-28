# AGENTS

Guidance for contributors (human and AI) working in this repository.

## 1) Project Scope

This repo is a Dart workspace with a Flutter package:

- Workspace root: `pubspec.yaml`
- Core package: `packages/vigil`
- Key docs: `README.md`, `ARCHITECTURE.md`, `STRETCH_GOALS.md`

Primary goal: maintain a reliable, minimal, TanStack Query-inspired server-state library for Flutter.

## 2) Non-Negotiable Standards

1. **Preserve architecture boundaries**
   - `lib/src/core/`: framework-agnostic primitives (prefer pure Dart, no Flutter imports).
   - `lib/src/`: handles and user-facing API behavior.
   - Flutter integration should stay thin (`query_mixin.dart`, provider wiring, lifecycle glue).

2. **Respect the state model**
   - Query state is dual-axis (`status` + `fetchStatus`).
   - Avoid simplifying into single-axis loading/data/error patterns.

3. **Keep public API intentional**
   - Public symbols must be exported from `packages/vigil/lib/vigil.dart`.
   - Avoid accidental API surface growth.

4. **Follow lint/style rules**
   - `prefer_const_constructors: true`
   - `prefer_const_declarations: true`
   - `avoid_print: true`
   - `prefer_single_quotes: true`

5. **Prefer minimal, root-cause fixes**
   - Fix upstream cause, not downstream symptoms.
   - Keep changes focused and small unless a broader refactor is required.

## 3) File Placement Rules

- New cache/retry/subscription primitives -> `packages/vigil/lib/src/core/`
- Query/mutation/infinite behavior -> `packages/vigil/lib/src/`
- Tests -> `packages/vigil/test/`
- Contributor-facing behavior/design rationale -> update `README.md` and/or `ARCHITECTURE.md`

## 4) Quality Bar for Changes

For any non-trivial behavior change:

1. Add or update tests in `packages/vigil/test/`
2. Keep docs aligned with behavior
3. Run analysis and tests before merging

Recommended commands (run from repo root using your terminal's working directory setting):

- `flutter pub get` (in `packages/vigil`)
- `flutter analyze` (in `packages/vigil`)
- `flutter test` (in `packages/vigil`)

## 5) Decision Checklist (Before PR/Merge)

- Does this change preserve layer boundaries?
- Is the dual-axis query model still correct?
- Are lint rules satisfied without suppressions?
- Are tests updated for new/changed behavior?
- Is the public API export list deliberate?
- Is documentation updated if user-facing behavior changed?

## 6) What to Avoid

- Mixing Flutter-only concerns into core primitives without strong reason
- Introducing print-based debugging in committed code
- Large unrelated refactors bundled with bug fixes
- Changing behavior without matching tests/docs
