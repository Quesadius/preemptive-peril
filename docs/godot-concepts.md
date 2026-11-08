# Godot for Professional Programmers

A concepts-first reference for someone who already knows how to write software, aimed at building a turn-based grid tactics game.

Written against **Godot 4.7** (current stable as of July 2026). Version-sensitive claims are flagged with ⚠️ — verify before betting architecture on them.

---

## 0. How to read this

You don't need a tutorial on loops. What you need is the engine's model of the world, because that's where your C++ instincts will mislead you. The sections are ordered by how much they'll bite you:

1. **Object model and memory** — the first thing that confuses systems programmers
2. **Nodes, scenes, the tree** — Godot's composition story
3. **Resources** — the most underused feature, and the one your game needs most
4. **GDScript** — 45 minutes of reading, genuinely
5. **Architecture and testing** — how to keep your engineering discipline inside a game engine
6. **Everything else** — input, rendering, UI, tooling, export, gotchas

---

## 1. What Godot actually is

Strip the marketing away and Godot is three things:

- **An object system** with reflection, a signal/observer mechanism, and reference counting
- **A scene tree** — a runtime graph of objects that receive lifecycle callbacks and propagate transforms
- **A serialization format** that can save and restore arbitrary subgraphs of that tree

Everything else — the renderer, the physics engine, the UI toolkit — is a set of node types plugged into that. There is remarkably little magic. Once you internalize the object model and the tree, the rest is API surface you look up as needed.

The engine is written in C++ and the editor is a Godot application built with the same node system your game uses. That's a useful sanity check: nothing in the editor uses capability your game can't reach.

**What this means for your project:** a grid tactics game uses maybe 15% of Godot. No physics, no 3D, no animation state machines, no navmesh. You are using it as a portable window + input + sprite + UI + audio + export layer, with a scene system for organizing screens. That's a great fit and it means the learning surface is much smaller than "learn Godot" sounds.

---

## 2. The object model and memory management

This is the part that trips up C++ programmers, because Godot has three different lifetime models and you must know which one you're in.

### The hierarchy

```
Object                    — base. Manual lifetime. You call free().
└── RefCounted            — reference counted. Freed automatically at refcount 0.
    └── Resource          — RefCounted + serializable + can live in a .tres/.res file
└── Node                  — Object. Owned by its parent once in the tree.
    └── CanvasItem → Node2D / Control
    └── Node3D
```

### The three lifetime models

**`Object`** — raw. You call `free()` yourself. You will almost never subclass this directly. Freeing an Object leaves dangling references; other variables pointing at it become invalid, and `is_instance_valid(obj)` is how you check. Treat it like `new`/`delete` and avoid it.

**`RefCounted`** — automatic. This is your `shared_ptr`. When the last reference goes out of scope, it's freed. **A GDScript file with no `extends` line implicitly extends `RefCounted`.** This is important: it means plain data/logic classes are memory-safe by default with zero effort.

```gdscript
# damage_calculator.gd  — no extends line, so it's RefCounted
class_name DamageCalculator

func compute(attacker: UnitState, defender: UnitState) -> int:
    ...
```

**`Node`** — tree-owned. Once you `add_child(n)`, the parent owns it and will free it when the parent is freed. To destroy a node yourself, call `queue_free()`, which defers the deletion to the end of the current frame. Calling `free()` on a node mid-frame while something is iterating the tree is a classic crash.

```gdscript
node.queue_free()          # safe, deferred to end of frame
node.free()                # immediate — only if you know nothing is holding it
is_instance_valid(node)    # false after free; note it stays true until the deferred free happens
```

⚠️ Gotcha: after `queue_free()`, the node is still alive and `is_instance_valid()` still returns `true` until the frame ends. If you need "logically dead now," set your own flag or remove it from your data structures immediately.

**Cycles are not collected.** Refcounting only. Two `RefCounted` objects holding each other leak. This matters if you build parent/child links in your data model — use a weak back-reference (`WeakRef` via `weakref(obj)`) or just store an ID/index instead of a pointer. For a tactics game, storing integer unit IDs rather than object references in your grid is both leak-proof and serialization-friendly.

### Practical rule for your project

> Game logic classes: plain scripts with no `extends` (→ `RefCounted`). Data tables: `Resource`. Anything on screen: `Node`.

That single rule keeps your rules engine out of the node system entirely, which is exactly what you want.

---

## 3. Nodes, scenes, and instancing

### Nodes

A node is an object in the tree with a name, a parent, children, and a set of lifecycle callbacks. Node types are the engine's vocabulary: `Sprite2D`, `Camera2D`, `AudioStreamPlayer`, `Button`, `Timer`, `TileMapLayer`.

Godot's composition model is **"compose by nesting nodes,"** not "attach components to an entity." If you're used to Unity's ECS-ish `GameObject + Components`, the mental translation is: a Unity GameObject with 5 components ≈ a Godot node with 5 children. It feels wasteful at first; it isn't. Nodes are cheap.

You extend behavior by attaching **one script** to a node. A node has at most one script. Reuse comes from inheritance (`extends Sprite2D`) or from composing child nodes that each have their own script.

### Scenes

A **scene** is a saved tree of nodes, in a `.tscn` file. That's the whole concept. A scene can be:

- Your entire game
- A single UI panel
- One unit with its sprite, health bar, and selection outline

**Scenes are the reuse unit.** A scene can be *instanced* inside another scene. When you edit the source scene, every instance updates. Instance-level overrides are stored as a diff in the parent scene file — so an instanced `Unit.tscn` with `team = 2` stores only that property.

Mentally: **a scene is a prefab, and also a class.** `PackedScene` is the loaded, uninstantiated form.

```gdscript
const UNIT_SCENE := preload("res://scenes/unit.tscn")   # PackedScene, loaded at parse time

func spawn_unit(coord: Vector2i) -> Node2D:
    var unit := UNIT_SCENE.instantiate() as Node2D      # allocate an instance
    unit.position = grid_to_world(coord)
    add_child(unit)                                     # now it's in the tree and alive
    return unit
```

`preload()` resolves at script-parse time (a compile-time constant — use it for anything known statically). `load()` resolves at runtime. `ResourceLoader.load_threaded_request()` for async loading of big things; you won't need it.

### The scene tree

There's exactly one live tree, reachable via `get_tree()` (returns `SceneTree`). It owns:

- The root `Window`
- The "current scene" (what `change_scene_to_*` swaps)
- Autoload singletons (see §9)
- Global pause state, node groups, frame signals

```gdscript
get_tree().change_scene_to_file("res://scenes/battle.tscn")
get_tree().change_scene_to_packed(BATTLE_SCENE)     # preferred — no runtime load hitch
get_tree().paused = true
get_tree().quit()
```

⚠️ `change_scene_to_*` is deferred — the swap happens at end of frame, not on the line you called it. Don't assume the new scene exists on the next statement.

**Groups** are a lightweight tagging system: `add_to_group("units")`, then `get_tree().get_nodes_in_group("units")`. Handy, but it's a global string-keyed lookup — fine for "pause everything," bad as your primary data model. Don't let your unit roster live in a group.

---

## 4. Lifecycle callbacks

The callbacks Godot calls on your node. All are `virtual`-ish: define them and they get called.

| Callback | When | Notes |
|---|---|---|
| `_init()` | Object construction | No tree, no children guaranteed. Rarely used on Nodes. |
| `_enter_tree()` | Node added to tree | **Top-down** (parent before children) |
| `_ready()` | Node and all children are in the tree | **Bottom-up** (children before parent). Called once. Your real constructor. |
| `_process(delta)` | Every rendered frame | Variable rate. Frame-dependent work, animation, input polling. |
| `_physics_process(delta)` | Fixed timestep (default 60 Hz) | Deterministic rate. |
| `_input(event)` | Every input event, early | Sees events before UI |
| `_unhandled_input(event)` | Input not consumed by UI | **Use this for gameplay input** |
| `_draw()` | On redraw | Immediate-mode custom drawing; trigger with `queue_redraw()` |
| `_exit_tree()` | Removed from tree | Cleanup |
| `_notification(what)` | Catch-all for engine notifications | `NOTIFICATION_WM_CLOSE_REQUEST`, `NOTIFICATION_APPLICATION_PAUSED`, etc. |

**The ordering rule that matters:** `_ready()` is bottom-up. When your parent's `_ready()` runs, every child's `_ready()` has already run. So parents can safely initialize from children, but children cannot depend on the parent being initialized. This is the opposite of what most people assume and causes a lot of first-week null errors.

**Turn off what you don't use.** `set_process(false)` / `set_physics_process(false)`. In a turn-based game, most nodes should have *no* per-frame callbacks at all — they're event-driven. Godot enables `_process` only if you define it, but explicitly disabling during idle states is free performance and clearer intent.

For your game: you likely won't use `_physics_process` at all. Animation tweens and input handling in `_process`/`_unhandled_input`, everything else purely event-driven.

---

## 5. Signals

Godot's observer pattern, and the primary decoupling mechanism.

```gdscript
# Declaring
signal unit_selected(unit_id: int)
signal turn_ended(team: int, remaining_actions: int)

# Emitting
unit_selected.emit(42)

# Connecting
button.pressed.connect(_on_button_pressed)
unit_selected.connect(_on_unit_selected)
unit_selected.connect(_on_unit_selected, CONNECT_ONE_SHOT)
unit_selected.connect(func(id): print(id))          # lambda

# With bound extra args
button.pressed.connect(_on_tile_clicked.bind(coord))

# Disconnecting
unit_selected.disconnect(_on_unit_selected)
```

`Signal` and `Callable` are first-class values in Godot 4 — you can pass them around, store them, return them. `some_node.some_signal` is a value.

**Signals are synchronous.** `emit()` calls every connected callable inline before returning. It's not a queue. If you need deferral, `connect(callable, CONNECT_DEFERRED)`.

**When to use signals:** child → parent communication, or notifying an unknown number of listeners. The rule of thumb is *"call down, signal up."* A parent can call methods on its children directly (it knows they exist). A child should not reach up and call into its parent (it doesn't know who it's attached to) — it emits and lets whoever's listening react.

**When NOT to use signals:** as a general-purpose event bus for your core game logic. Signals are Godot-specific, hard to test headlessly, and make control flow non-obvious when overused. Your rules engine should return data, not emit signals. Let the *presentation* layer translate state deltas into signals.

⚠️ Connecting to a freed node's signal, or leaving a connection to a node you free, is a common source of errors. Connections are automatically cleaned up when either end is freed, but the code that assumed the connection persists is what breaks.

---

## 6. Resources — the feature to actually lean on

A `Resource` is a `RefCounted` object that can be **serialized to a file, edited in the inspector, and shared by reference between many objects.** Textures, audio streams, fonts, scenes, and materials are all Resources. So are your own data types, and this is where most people underuse the engine.

For a tactics game, this is how your entire game-balance layer should be expressed.

```gdscript
# res://data/unit_type.gd
class_name UnitType
extends Resource

@export var display_name: String = ""
@export var texture: Texture2D
@export_range(1, 20) var movement: int = 3
@export var movement_class: MovementClass       # another custom Resource
@export var attack_range_min: int = 1
@export var attack_range_max: int = 1
@export var cost: int = 1000
@export var max_ammo: int = 9
@export var max_fuel: int = 99
## Damage this unit deals against each other unit type, as base percentages.
@export var base_damage: Dictionary[StringName, int] = {}
```

Now `infantry.tres`, `tank.tres`, `artillery.tres` are **data files editable in the inspector by a non-programmer**, version-controlled as text, hot-reloadable, and referenced by every unit instance without duplication.

Same pattern for `TerrainType` (defense stars, movement cost per movement class), `COPower`, `MapDefinition`.

### Key Resource properties

- **Shared by default.** Load `infantry.tres` twice and you get the same object. Mutating it at runtime mutates it for everyone. Call `duplicate()` if you need a per-instance copy. This is a real bug source — treat loaded Resources as immutable.
- **`.tres` is text, `.res` is binary.** Always use `.tres` for anything hand-authored: it diffs and merges in git.
- **Exported properties appear in the inspector automatically.** No custom editor code needed for 90% of cases.
- **Resources can reference other Resources**, giving you a data graph editable entirely in the editor.

### Useful `@export` annotations

```gdscript
@export var hp: int = 10
@export_range(0, 100, 5) var accuracy: int = 75      # min, max, step — gives a slider
@export_enum("Land", "Sea", "Air") var domain: int = 0
@export_multiline var description: String = ""
@export_file("*.tscn") var scene_path: String = ""
@export_color_no_alpha var team_color: Color = Color.RED
@export_group("Combat")                              # inspector organization
@export var attack: int = 5
@export_category("Debug")
@export var verbose: bool = false
```

---

## 7. GDScript for C++ programmers

The language is small. Here is essentially all of it that matters.

### Structure

```gdscript
class_name Unit            # optional: registers a global type name engine-wide
extends Node2D             # optional: defaults to RefCounted

## Doc comment (double #) — shows in the editor's help
const MAX_HP := 10         # constant, type inferred
static var instances := 0  # static member

enum State { IDLE, MOVING, DONE }

@export var team: int = 0                  # editable in inspector, serialized
@onready var sprite: Sprite2D = $Sprite2D  # assigned during _ready()

var _hp: int = MAX_HP                      # leading underscore = "private" by convention only

func _ready() -> void:
    pass

func take_damage(amount: int) -> bool:
    _hp -= amount
    return _hp <= 0

static func from_type(t: UnitType) -> Unit:
    ...
```

### Typing

Static typing is **optional but you should use it everywhere**. It's not just documentation:

- Typed code is checked at parse time and at runtime
- Typed GDScript is meaningfully faster (the VM can skip dynamic dispatch)
- The editor's autocomplete only really works with types

```gdscript
var a := 5                    # inferred int
var b: float = 5              # explicit, coerced
var c: Array[Vector2i] = []   # typed array — element type enforced
var d: Dictionary[StringName, int] = {}   # typed dictionary
func f(x: int, y: String = "") -> void:
```

⚠️ Turn on **`debug/gdscript/warnings/untyped_declaration`** in Project Settings and set it to Error. This is the single highest-value setting for someone coming from a typed language. It converts GDScript from "dynamic scripting language" to "statically checked language with inference," which is much closer to what you're used to.

### Syntax notes for a C++ reader

| C++ | GDScript |
|---|---|
| `{ }` blocks | Indentation (tabs by default) |
| `&&`, `\|\|`, `!` | `and`, `or`, `not` (the symbols also work) |
| `nullptr` | `null` |
| `a ? b : c` | `b if a else c` |
| `for (int i=0;i<n;i++)` | `for i in n:` or `for i in range(a, b, step):` |
| `switch` | `match` (pattern matching — more powerful) |
| `dynamic_cast<T*>` | `as T` (returns `null` on failure) |
| `typeid` / `instanceof` | `is` |
| `std::vector` | `Array` / `PackedInt32Array` etc. |
| `std::unordered_map` | `Dictionary` |
| `#include` | Nothing — use `class_name` or `preload()` |
| Lambdas | `func(x): return x * 2` |

```gdscript
match state:
    State.IDLE:
        pass
    State.MOVING, State.DONE:      # multiple patterns
        pass
    var other:                     # binds, acts as default
        push_error("unexpected %s" % other)

# Destructuring in match
match coord_pair:
    [var x, var y]:
        print(x, y)
    {"type": "move", "to": var dest}:
        print(dest)
```

### Things that will bite you

**Integer division truncates, same as C++** — but there's no compiler warning and no types on literals to remind you. `var pct := 3 / 4` is `0`. Write `3.0 / 4.0`.

**`Array` and `Dictionary` are reference types.** Assignment aliases; it does not copy.

```gdscript
var a := [1, 2, 3]
var b := a              # b IS a
var c := a.duplicate()  # shallow copy
var d := a.duplicate(true)  # deep copy
```

This is the #1 source of "why did my map data change" bugs. `PackedInt32Array`, `PackedVector2Array` etc. are **value types** and copy-on-write — which is both faster and safer for grid data. Use them for your tile arrays.

**`Vector2i` for grid coordinates.** Integer vector type, hashable, usable as a Dictionary key. Don't roll your own coordinate struct.

**`StringName` for repeated identifiers.** Written `&"my_action"`. Interned, compared by pointer. Use for input action names, group names, signal names, and any string used as a dictionary key in a hot loop.

**No interfaces.** GDScript has no formal interface concept. You get duck typing (`if obj.has_method("act")`), or abstract base classes. ⚠️ Recent 4.x added an `@abstract` annotation for classes and methods — verify availability in your version and prefer it to convention-based abstraction if present.

**No namespaces.** `class_name` registers globally. Prefix or accept the flat namespace. Inner classes exist (`class Foo:` inside a file) and are namespaced under the outer script, which is one workaround.

**Coroutines via `await`.** Suspends the function until a signal fires:

```gdscript
func play_attack_sequence() -> void:
    animation_player.play("attack")
    await animation_player.animation_finished
    await get_tree().create_timer(0.2).timeout
    hud.show_damage(dmg)
```

This is enormously useful for turn-based games — animation sequencing reads as straight-line code instead of a callback pyramid. `await` on a function that returns a value works too. Note: awaiting inside a function makes it return a `Signal` to its caller; be careful about whether callers need to `await` you back.

**Assertions:** `assert(cond, "message")` — **stripped entirely in release builds**, like `NDEBUG`. Use `push_error()` / `push_warning()` for things that must survive to release.

### Threading

`Thread`, `Mutex`, `Semaphore`, and `WorkerThreadPool` exist. Most of the scene tree is **not** thread-safe — you can compute on a thread, but node manipulation must be marshalled back to the main thread (`call_deferred`).

⚠️ Threads on web export require cross-origin isolation headers (`COOP`/`COEP`) on your host. itch.io supports this via a project setting; some hosts don't. If your AI search needs a background thread and you care about web, verify this early — it's a deployment constraint, not a code one.

For your game: a 30×20 map AI almost certainly doesn't need threads. Time-slice across frames with a coroutine before reaching for concurrency.

---

## 8. Getting references to other nodes

Four mechanisms, in rough order of preference:

```gdscript
# 1. Exported node reference — set in the editor, refactor-safe, explicit dependency
@export var health_bar: ProgressBar

# 2. Scene-unique name — right-click node in editor → "Access as Unique Name"
@onready var health_bar: ProgressBar = %HealthBar

# 3. Node path — brittle, breaks when you reorganize the tree
@onready var health_bar: ProgressBar = $UI/Panel/HealthBar
@onready var health_bar := get_node("UI/Panel/HealthBar") as ProgressBar

# 4. Group lookup — for "all of a kind," not for a specific one
var units := get_tree().get_nodes_in_group(&"units")
```

`$Foo/Bar` is sugar for `get_node("Foo/Bar")`. `%Foo` is sugar for `get_node("%Foo")` and searches the whole scene for a node marked unique — this is the idiomatic fix for deep paths.

**Prefer `@export` node references.** They make dependencies explicit and visible, they survive tree reorganization, and they're the closest thing Godot has to constructor injection. `%UniqueName` is a good second choice.

Never `get_parent().get_parent().do_thing()`. That's the "call down, signal up" rule being violated and it will make the node non-reusable.

---

## 9. Autoloads (singletons)

Project Settings → Globals → Autoload. Registers a script or scene as a globally accessible node, instantiated before the main scene, present for the entire run.

```gdscript
# Registered as "GameState"
GameState.current_turn
EventBus.unit_died.emit(id)
```

Legitimate uses: audio manager, settings/save manager, scene transition manager, a global event bus.

**Discipline note:** an autoload is a global variable with all the usual costs — it hides dependencies, complicates testing, and makes ownership ambiguous. For your project, I'd cap it at two or three, and specifically **keep your rules engine out of an autoload.** The whole point of a pure core is that you can instantiate a fresh one per test. A singleton forecloses that.

---

## 10. Input

Define named actions in Project Settings → Input Map. Never hardcode key codes; the indirection is what gives you rebinding, controller support, and touch equivalence for free.

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"confirm"):
        _confirm_selection()
        get_viewport().set_input_as_handled()      # consume it
    elif event is InputEventMouseButton and event.pressed:
        var coord := world_to_grid(get_global_mouse_position())
        _on_tile_clicked(coord)

# Polling (for continuous movement — use in _process)
if Input.is_action_pressed(&"cursor_right"):
    ...
var axis := Input.get_vector(&"left", &"right", &"up", &"down")
```

**Event flow:** `_input` on all nodes → GUI (Control nodes) → `_unhandled_input`. Use `_unhandled_input` for gameplay so UI naturally gets first refusal on clicks. Consume with `get_viewport().set_input_as_handled()`.

For portability, map the same actions to keyboard, gamepad, and touch. A turn-based cursor-and-confirm game maps to touch almost trivially, which is a real advantage of the genre.

---

## 11. 2D rendering and coordinates

```
CanvasItem                 — anything 2D drawable
├── Node2D                 — has a 2D transform. Game world objects.
└── Control                — has a rect + anchoring + focus. UI.
```

Both draw; they differ in layout model. Don't put UI under `Node2D` or game objects under `Control`.

**Draw order** is tree order (later siblings draw on top), modified by `z_index` within the same `CanvasLayer`. `y_sort_enabled` on a parent sorts children by Y position — the standard trick for isometric or overlapping-sprite depth. For a flat top-down grid game you'll mostly use explicit layer nodes: terrain layer, then unit layer, then overlay layer, then UI.

**`CanvasLayer`** breaks out of the camera transform — put HUD in one so it doesn't move with `Camera2D`.

**Custom drawing** for range overlays and grid lines:

```gdscript
func _draw() -> void:
    for coord in reachable_tiles:
        draw_rect(Rect2(grid_to_world(coord), TILE_SIZE), Color(0, 0.5, 1, 0.35))

func set_reachable(tiles: Array[Vector2i]) -> void:
    reachable_tiles = tiles
    queue_redraw()      # schedules _draw() for this frame — never call _draw() directly
```

`_draw()` is immediate-mode and only re-runs when you call `queue_redraw()`. For a turn-based game that's ideal: redraw the overlay on selection change, never per frame.

**Pixel art settings** (get these right on day one, they're painful to retrofit):
- Project Settings → Rendering → Textures → **Default Texture Filter = Nearest**
- Project Settings → Display → Window → Stretch **Mode = `canvas_items`** (or `viewport` for strict pixel snapping), **Aspect = `keep`** or `expand`
- Set a base resolution that's an integer fraction of common targets

### TileMapLayer

⚠️ `TileMap` is deprecated; **use `TileMapLayer`** — one node per visual layer, sharing a `TileSet` resource. Existing `TileMap` scenes still load but every current tutorial and plugin assumes the new node.

```gdscript
@export var terrain_layer: TileMapLayer

func terrain_at(coord: Vector2i) -> TerrainType:
    var data := terrain_layer.get_cell_tile_data(coord)
    return data.get_custom_data("terrain_type") if data else null
```

`TileSet` supports **custom data layers** — arbitrary typed values per tile. That's how you attach defense bonus and movement cost to tiles without a parallel data structure.

**But:** for the tactics-game core, I'd treat the TileMapLayer as *rendering only* and keep the authoritative terrain grid in your own `PackedInt32Array` inside the rules engine. The TileMapLayer is a view of it. That preserves the headless-testable core and avoids your logic depending on a node.

### Pathfinding

`AStarGrid2D` is built in and supports solid cells and per-cell `weight_scale`. Worth knowing about. However, for Advance Wars mechanics you need:

- Movement cost varying by **unit movement class** (treads vs. tires vs. foot vs. air vs. sea)
- Full **reachable set** within a budget, not a single path
- Blocking by enemy units but pass-through for allies

That's a bounded Dijkstra / uniform-cost search over your own grid, and it's ~40 lines. Write it yourself in the pure core. Use `AStarGrid2D` only if you later want a cursor-to-destination path preview and it happens to fit.

---

## 12. The UI system

`Control` nodes with an anchor/margin layout system plus containers.

Key idea: **either you position a Control manually, or a Container positions it — never both.** A Control inside a `VBoxContainer` has its position and size overwritten by the parent every layout pass. Fighting this is the #1 Godot UI frustration.

Common containers: `VBoxContainer`, `HBoxContainer`, `GridContainer`, `MarginContainer`, `PanelContainer`, `CenterContainer`, `ScrollContainer`, `TabContainer`.

Sizing is controlled by `size_flags_horizontal` / `size_flags_vertical` (`FILL`, `EXPAND`, `SHRINK_CENTER`) and `custom_minimum_size`. Roughly analogous to flexbox: `EXPAND` is `flex-grow`.

**Theming:** a `Theme` resource sets fonts, colors, and styleboxes for whole classes of controls. Set it once at the root; children inherit. Per-node overrides exist (`add_theme_color_override`) but a Theme resource is the maintainable path. Set up a Theme early — retrofitting one across 40 hand-styled controls is miserable.

For a tactics game the UI load is substantial: unit info panel, terrain panel, CO panel, build menu, action menu, map screen, options. This is genuinely where Godot pays for itself versus SDL, and it's worth budgeting real time to learn.

---

## 13. Filesystem, saving, and paths

| Path | Meaning |
|---|---|
| `res://` | Project resources. **Read-only in exported builds.** |
| `user://` | Per-user writable dir. Platform-appropriate location, handled for you. |

Never use OS paths. `user://` resolves to `%APPDATA%`, `~/.local/share`, iOS app sandbox, or IndexedDB-backed storage on web, transparently. This is one of the concrete portability wins over rolling your own.

```gdscript
func save_game(state: Dictionary) -> Error:
    var f := FileAccess.open("user://save_1.json", FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_string(JSON.stringify(state))
    return OK
```

Options: JSON (portable, debuggable, version-tolerant — good default), `FileAccess.store_var()` (binary, fast, brittle across versions), or `ResourceSaver` with a custom Resource (integrates with the inspector, but couples your save format to your class layout — and ⚠️ never `load()` a `.tres` from an untrusted source; resource files can reference scripts).

⚠️ **On web, `user://` writes are async under the hood.** Call `OS.get_data_dir()`-adjacent flush semantics carefully; in practice, call `JavaScriptBridge`-free `FileAccess` normally but be aware saves may not persist if the tab closes immediately. Test this specifically.

Since your game state is already a clean serializable structure (if you follow §14), saving is nearly free: serialize the core state object, done. Replays and undo fall out of the same design.

---

## 14. Architecture: keeping your engineering discipline

This is the section that matters most for you, given how you set up your C++ projects.

### The pure core

Structure the project so the rules engine has **zero dependency on Node, on the tree, or on rendering.**

```
res://
├── core/                      # pure logic — no Node, no rendering, no signals
│   ├── game_state.gd          # extends RefCounted
│   ├── action.gd              # extends RefCounted — Move, Attack, Capture, Build, EndTurn
│   ├── rules.gd               # static funcs: apply(state, action) -> Result
│   ├── movement.gd            # reachable_set(state, unit_id) -> Dictionary[Vector2i, int]
│   ├── combat.gd              # damage(state, attacker, defender) -> DamageOutcome
│   └── fog.gd                 # visibility(state, team) -> PackedByteArray
├── data/                      # Resources: unit types, terrain types, COs
├── ai/                        # consumes core only — no Node dependency
├── presentation/              # Nodes: renders state, translates input to Actions
├── ui/
└── tests/
```

The contract:

```gdscript
# core/rules.gd
class_name Rules

## Returns null if the action is illegal.
static func validate(state: GameState, action: Action) -> ActionError:
    ...

## Pure. Does not mutate `state`. Returns the successor state and an event log
## that the presentation layer replays as animation.
static func apply(state: GameState, action: Action) -> ApplyResult:
    ...
```

What this buys you, all at once:

- **Testability.** `Rules.apply()` is a pure function over plain data. Test it headlessly with no engine window.
- **Undo.** Keep the action list, replay from the initial state. This is exactly the "cancel before confirming" behavior players expect from Advance Wars, and it's free.
- **Replays and save files.** Initial state + action list *is* the replay format, and it's tiny.
- **AI.** The AI runs the same `apply()` to search. No duplicate rules implementation — the classic source of AI/player rule divergence.
- **Portability beyond Godot.** If you ever want a web version, a server-authoritative multiplayer mode, or a port, the core moves and only the shell is rewritten. Which is the decoupled-core pattern you already like, expressed in a different language.

**The discipline to enforce:** nothing in `core/` may reference `Node`, `get_tree()`, `preload()` of a scene, or any signal. If you can't run it with `--headless` and no scene loaded, it doesn't belong in `core/`.

### Testing

Two mature frameworks: **GUT** and **gdUnit4** (both in the Asset Library). gdUnit4 has somewhat better CI integration and assertion ergonomics; GUT has been around longer. Either is fine.

```bash
# Headless CI run
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Both frameworks report exit codes suitable for CI, and both can emit JUnit XML for GitHub Actions.

**Honest expectation setting:** this is not GoogleTest. Coverage tooling for GDScript is weak — ⚠️ `godot-gdscript-coverage`-style tools exist but are community-maintained and not comparable to `llvm-cov`. You will not get a reliable 100%-line-coverage gate the way you have in your C++ setup.

What you *can* do, and should:

- Enforce that `core/` is pure by a lint script — grep for `get_tree`, `extends Node`, `preload(".*tscn")` in `core/` and fail CI. Mechanical enforcement in the same spirit as your existing hooks.
- Property-test the rules: generate random legal action sequences, assert invariants (unit count conserved, HP in range, no two units per tile, `apply` is deterministic).
- Golden-file test the AI: fixed seed, fixed map, assert the chosen action sequence is stable. Catches unintended behavior drift.
- Run the full test suite headless in GitHub Actions on every push. Godot has an official Docker image and a well-known `--headless` story; this part is easy.

### Static analysis and formatting

- `gdlint` / `gdformat` from the **gdtoolkit** package (pip-installable). Wire into a pre-commit hook — same role as clang-format in your C++ setup.
- Godot's own warning system, with `untyped_declaration` and `unsafe_method_access` promoted to errors, is your closest analogue to a strict compiler.
- `godot --headless --check-only --script <file>` for parse validation in CI.

---

## 15. Tooling and workflow

**Editor.** Built-in script editor is serviceable but weak. Use an external editor — VS Code with the `godot-tools` extension gives you LSP autocomplete, debugging, and breakpoints against the running game. Set it in Editor Settings → Text Editor → External. JetBrains Rider has excellent Godot support if you use C#.

**Debugger.** Real breakpoints, watches, call stack, remote scene tree inspection (you can inspect and modify live node properties while the game runs — genuinely great). Profiler with per-function timings, plus a separate visual profiler for GPU.

**Hot reload.** Script changes apply to the running game. Not universal (changing exported variables or class structure often requires a restart) but the fast loop is real and it's a big part of why iteration is faster than a C++ compile cycle.

**`@tool` scripts** run in the editor itself. This is how you'd build a custom map editor inside Godot rather than as a separate application — a significant time saver.

```gdscript
@tool
extends Node2D

func _process(_delta: float) -> void:
    if Engine.is_editor_hint():
        queue_redraw()   # live-preview grid overlay while editing
```

⚠️ `@tool` scripts run in the editor process. An infinite loop or a null deref crashes the editor and can corrupt an unsaved scene. Guard everything with `Engine.is_editor_hint()`.

### Version control

`.gitignore`:

```
# Godot 4
.godot/
/android/
*.translation
```

**Do commit:** `.tscn`, `.tres`, `.gd`, `project.godot`, `export_presets.cfg` (⚠️ scrub credentials — it can contain keystore passwords), and **`.uid` files** (Godot 4.4+ resource UIDs — not committing these breaks references for collaborators).

**Do not commit:** `.godot/` (import cache, regenerated).

Set the text editor to use LF and enable the Git plugin if you want inline diffs, though external git is fine.

**Merge conflicts in `.tscn` files are the real pain.** They're text, but they're structured text with internal ID references, and a merge that looks clean can produce a broken scene. Mitigations: keep scenes small and composed rather than monolithic, keep logic in `.gd` files (which merge normally), and treat scene files as effectively lock-required if you ever collaborate.

---

## 16. Export and portability

Export templates are prebuilt engine binaries per platform; the editor bundles your project with one. Configure presets in Project → Export.

| Target | Notes |
|---|---|
| Windows / macOS / Linux | Straightforward. macOS needs codesigning + notarization for distribution outside your own machine. |
| Android | Needs Android SDK + a debug keystore; the editor walks you through it. Google Play requires signing config + AAB. |
| iOS | **Requires macOS + Xcode.** Export produces an Xcode project you build and sign. Apple Developer account required, even for device testing. |
| Web | WASM + WebGL2/WebGPU. Needs correct MIME types and, for threads, COOP/COEP headers. itch.io works well. |

**The C# caveat, restated precisely:** ⚠️ as of Godot 4.7, C# web export is still not officially supported. A `.NET`-on-web prototype has been demoed and community builds exist, but it is not a shipped, supported path. If web export is a requirement, **GDScript is the safe choice.** Verify current status at `godotengine.org` before deciding, since this has been in motion.

**Realistic size:** an exported 2D game with modest assets lands in the 30–70 MB range per desktop platform; web builds compress to roughly 15–30 MB. Fine for a tactics game.

---

## 17. Gotchas checklist

Things that cost people a day each:

- `_ready()` is **bottom-up**. Children initialize before parents.
- `Array`/`Dictionary` assignment **aliases**. Use `.duplicate()` / `.duplicate(true)`.
- Integer division truncates silently.
- `queue_free()` is deferred; the node is still valid this frame.
- Loaded `Resource`s are **shared**. Mutating one mutates it everywhere.
- Manual positioning inside a `Container` is overwritten every layout pass.
- `_draw()` only runs after `queue_redraw()`; never call `_draw()` yourself.
- `@onready` runs at `_ready`, so it can't be used for values needed in `_init` or `_enter_tree`.
- `change_scene_to_*` is deferred to end of frame.
- Circular `preload()` between two scripts fails at parse time. Break with `load()` or restructure.
- `assert()` is compiled out in release. Use `push_error()` for anything that must survive.
- The scene tree is not thread-safe. Marshal with `call_deferred()`.
- Signal connections to freed nodes are cleaned up, but code assuming the connection persists is not.
- Web export + threads requires COOP/COEP headers from your host.
- `.uid` files must be committed (4.4+).
- Renaming a `class_name` doesn't update `.tscn` references automatically in all cases — check after refactors.

---

## 18. A learning path that fits your project

Roughly two weeks of evenings, each step producing a real piece of the game.

**Day 1 — orientation.** Install 4.7. Do the official "Your first 2D game" (the Dodge the Creeps tutorial) end to end. It's two hours and it teaches nodes, scenes, signals, and export in the only way that sticks. Don't skip it because it looks trivial.

**Day 2 — the spike.** Blank project. A `TileMapLayer` with two tile types, a `Camera2D`, and a cursor that snaps to the grid, moves with keyboard and mouse, and highlights the hovered tile with `_draw()`. This is the "does GDScript annoy me" test, and it's real code you'll keep.

**Day 3–4 — the core, headless.** No rendering at all. Write `GameState`, `Action`, `Rules.apply()`, and bounded-Dijkstra movement. Install gdUnit4 and get `godot --headless` running your tests. Get CI green on GitHub Actions. Establishing this before any UI exists is what keeps the architecture honest — it's much harder to extract a pure core later than to never contaminate it.

**Day 5–6 — data layer.** Define `UnitType` and `TerrainType` as `Resource`s. Author four units and six terrain types as `.tres` files in the inspector. Wire the core to consume them.

**Day 7–8 — presentation.** Render state. Unit sprites, movement range overlay, selection, and the move → confirm → cancel loop. This is where `await` sequencing and signals earn their keep.

**Day 9–10 — UI.** Learn `Control` and containers properly by building the unit info panel and the action menu. Set up a `Theme` resource before you style anything.

**Day 11–12 — export everywhere.** Export to desktop, web, and Android early, while the project is small. Finding a platform problem now costs an hour; finding it at month six costs a redesign.

**Then — AI, fog of war, map editor, COs.** The long tail.

---

## 19. Reference

### Official docs worth bookmarking

- Class reference (`docs.godotengine.org` → Classes) — the actual API, searchable, also available offline in-editor via F1
- "Godot's design philosophy" and "Best practices" sections in the manual — short, unusually good, explains *why* the engine works the way it does
- "Scene organization" and "When to use scenes vs scripts" — directly relevant to your structure questions

### Community

- The official Godot forum and `r/godot` are both reasonable signal.
- Asset Library for GUT/gdUnit4, gdtoolkit, and dialogue/save plugins.

### Quick command reference

```bash
godot --headless --path . -s res://scripts/tool.gd    # run a script headlessly
godot --headless --export-release "Web" build/index.html
godot --headless --check-only --script res://core/rules.gd
godot --path . --debug-collisions
godot --main-pack game.pck
gdformat core/ && gdlint core/                        # from gdtoolkit
```

### The three-sentence summary

Godot is a scene tree of nodes with lifecycle callbacks, plus a serializable Resource system for data. GDScript is a small Python-like language that you should write with static types turned into errors. Keep your rules engine as pure `RefCounted` classes with no tree dependency, and everything you care about — testing, undo, replays, AI, future portability — falls out of that one decision.
