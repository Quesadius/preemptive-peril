# Preemptive Peril — Project Guidance

Godot 4.7 / GDScript. Turn-based grid tactics.

## Read first

- `docs/architecture.md` — the authoritative file tree, class list, and method signatures. **Follow it.** If you believe it's wrong, say so and stop; do not silently deviate.
- `docs/godot-concepts.md` — engine reference. Background, not instructions.

## The one rule that matters

`core/`, `ai/`, and `data/` are **pure**. Files under those directories must never:

- `extends Node` or any Node subclass
- reference `get_tree()`, `get_node()`, `Engine`, `Input`, `Viewport`, or any rendering API
- `preload()` or `load()` a `.tscn`
- declare a `signal`
- print to stdout (use `push_error` / `push_warning`)

Everything under those paths must run under `godot --headless` with no scene loaded. `tools/check_core_purity.sh` enforces this and runs on every edit. If it fails, fix the file — do not weaken the check.

Presentation talks to core in exactly one direction:

```
input -> Action -> Rules.validate() -> Rules.apply() -> Array[GameEvent] -> animation
```

Presentation never mutates `GameState` directly. Core never emits signals.

## GDScript conventions

- **Static typing is mandatory.** Every variable, parameter, and return type annotated. `untyped_declaration` is set to Error in project settings; untyped code will not parse.
- Tabs for indentation. `gdformat` runs automatically on save — do not hand-format.
- `snake_case` for files, variables, functions. `PascalCase` for `class_name`. `_leading_underscore` for private members.
- Prefer `PackedInt32Array` / `PackedVector2Array` over `Array` for grid data — value semantics, copy-on-write.
- Use `Vector2i` for all grid coordinates. Never a custom coord struct, never a packed int.
- Use `StringName` (`&"key"`) for identifiers used as dictionary keys or compared in loops.
- `##` doc comments on every public method in `core/`.

## Determinism

`GameState.rng` is a seeded `DeterministicRng`. It is the **only** source of randomness in the entire project.

- Never call `randi()`, `randf()`, or `RandomNumberGenerator` outside `core/util/deterministic_rng.gd`.
- Never advance the RNG outside `Rules.apply()`.
- Replaying a serialized action log must reproduce an identical final state. There is a test for this; keep it green.

## Testing

- Framework: gdUnit4. Tests live in `tests/`, mirroring the `core/` structure.
- Every new function in `core/` ships with tests in the same change. Not a follow-up.
- Run: `./tools/run_tests.sh`. This runs headless and gates the Stop hook — if tests fail, keep working.
- Fixtures go in `tests/fixtures/` as small hand-verifiable maps (5x5 or smaller) with expected results written out by hand in the test, not generated.

Invariants to assert after any action (see `tests/property/`):

- `occupancy` agrees with `units`; no two units share a coord
- HP in 1..100; fuel and ammo within type maxima
- Every loaded unit's `carrier_id` points at a carrier whose `cargo` contains it
- Funds never negative
- Replaying the event log against a clone of the pre-state reproduces the post-state

## Data

Balance values live in `.tres` resources under `data/`, never in code. If you need a number that isn't in `Ruleset`, add an `@export` field to the schema rather than hardcoding it.

Unit and terrain identity in save files is `key: StringName`, never an array index.

## Scenes

**Do not hand-author `.tscn` files unless explicitly asked.** Write the `.gd` script with `@export` fields for its dependencies; the scene gets wired in the Godot editor. If a task requires a scene, write the script and list the node structure the human should build.

## Workflow

- After adding or modifying anything under `data/`, run `godot --headless --import` so the resource cache is current.
- Parse-check any script you write: `godot --headless --check-only --script <path>`.
- Work one milestone at a time (see `docs/architecture.md` §13). Do not scaffold ahead of the current milestone.
- Commit messages: `<area>: <imperative summary>`, e.g. `movement: add weather cost modifiers`.

## Things not to do

- Do not add autoloads. There are three, they are in `autoload/`, and that is the budget.
- Do not add a signal to `core/`.
- Do not introduce a second implementation of legality. `ActionGenerator` is the only source of "what is legal" — the UI and the AI both consume it.
- Do not split a move and its terminal verb into two Actions. A `UnitAction` carries both.
- Do not read raw `unit.hp` in presentation. Use `display_hp()`.
- Do not let the AI read `GameState` directly. It consumes a fog-filtered `StateView`.
