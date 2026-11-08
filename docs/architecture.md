# Preemptive Peril — Architecture Outline

Godot 4.7 / GDScript. Structured around a headless-testable pure core with a swappable presentation shell.

---

## 1. Layer map and dependency rules

```
┌──────────────────────────────────────────────────────────┐
│  presentation/  ui/            Nodes, rendering, input   │
│         │  depends on ↓                                  │
├──────────────────────────────────────────────────────────┤
│  ai/                           Pure. Consumes core.      │
│         │  depends on ↓                                  │
├──────────────────────────────────────────────────────────┤
│  core/                         Pure logic. RefCounted.   │
│         │  depends on ↓                                  │
├──────────────────────────────────────────────────────────┤
│  data/                         Resources. Inert data.    │
└──────────────────────────────────────────────────────────┘
```

**The invariant, enforced in CI:** nothing under `core/`, `ai/`, or `data/` may reference `Node`, `get_tree()`, `Engine`, a `.tscn`, or declare a `signal`. If it can't run under `godot --headless` with no scene loaded, it's in the wrong folder.

Presentation never mutates state. It sends `Action` objects to the core and renders the `GameEvent` list that comes back.

---

## 2. File tree

```
res://
├── project.godot
├── core/
│   ├── state/
│   │   ├── game_state.gd            # root aggregate
│   │   ├── map_state.gd             # terrain + property ownership grid
│   │   ├── unit_state.gd            # per-unit mutable data
│   │   ├── player_state.gd          # funds, CO, power meter
│   │   └── game_config.gd           # fog on/off, weather mode, rules variant
│   ├── actions/
│   │   ├── action.gd                # abstract base
│   │   ├── unit_action.gd           # move + terminal verb (the atomic AW turn unit)
│   │   ├── build_action.gd
│   │   ├── power_action.gd
│   │   └── end_turn_action.gd
│   ├── events/
│   │   ├── game_event.gd            # abstract base
│   │   └── events.gd                # concrete event structs
│   ├── rules/
│   │   ├── rules.gd                 # validate() / apply() — the front door
│   │   ├── movement.gd              # reachable set, path cost, path validation
│   │   ├── combat.gd                # damage, counterattack, ammo
│   │   ├── capture.gd
│   │   ├── supply.gd                # resupply, repair, fuel drain
│   │   ├── transport.gd             # load / unload / launch
│   │   ├── economy.gd               # income, build legality
│   │   ├── fog.gd                   # visibility computation
│   │   ├── weather.gd
│   │   ├── victory.gd               # win/loss conditions
│   │   └── turn_flow.gd             # start-of-turn and end-of-turn sequences
│   ├── query/
│   │   ├── action_generator.gd      # enumerate legal actions — shared by UI and AI
│   │   ├── threat.gd                # "what can reach/hit this tile"
│   │   └── state_view.gd            # fog-filtered read-only projection of state
│   └── util/
│       ├── grid.gd                  # coord math, neighbors, manhattan, bounds
│       ├── deterministic_rng.gd     # seeded PRNG — replay-critical
│       └── ids.gd                   # id allocation
│
├── data/
│   ├── schema/
│   │   ├── ruleset.gd               # bundles every table; the balance root
│   │   ├── unit_type.gd
│   │   ├── terrain_type.gd
│   │   ├── movement_class.gd
│   │   ├── weapon_profile.gd
│   │   ├── damage_table.gd
│   │   ├── co_profile.gd
│   │   ├── co_power.gd
│   │   └── map_definition.gd
│   ├── rulesets/
│   │   └── classic.tres
│   ├── units/                       # infantry.tres, mech.tres, tank.tres, ...
│   ├── terrain/                     # plains.tres, forest.tres, city.tres, ...
│   ├── movement_classes/            # foot.tres, boots.tres, treads.tres, ...
│   ├── cos/
│   └── maps/                        # *.tres MapDefinition
│
├── ai/
│   ├── ai_player.gd                 # abstract: choose_action(view) -> Action
│   ├── profiles/ai_profile.gd       # Resource: aggression, weights, difficulty
│   ├── scoring/
│   │   ├── evaluator.gd             # static position eval
│   │   ├── threat_map.gd
│   │   └── influence_map.gd
│   ├── behaviors/
│   │   ├── capture_behavior.gd
│   │   ├── attack_behavior.gd
│   │   ├── build_behavior.gd
│   │   └── retreat_behavior.gd
│   └── simple_ai.gd                 # greedy one-ply — the first working AI
│
├── presentation/
│   ├── battle.tscn / battle.gd      # scene root, owns core state + controller
│   ├── battle_controller.gd         # input state machine → Action
│   ├── event_player.gd              # GameEvent list → animation coroutine
│   ├── map_renderer.gd              # TileMapLayers, property ownership tinting
│   ├── unit_layer.gd                # spawns/pools UnitView by unit id
│   ├── unit_view.tscn / unit_view.gd
│   ├── overlay_layer.gd             # move range, attack range, path arrow (_draw)
│   ├── fog_layer.gd
│   ├── cursor.tscn / cursor.gd
│   ├── camera_rig.gd
│   └── battle_animation.tscn        # optional cut-in combat animation
│
├── ui/
│   ├── theme/main_theme.tres
│   ├── hud.tscn / hud.gd
│   ├── panels/terrain_info_panel.tscn
│   ├── panels/unit_info_panel.tscn
│   ├── panels/damage_preview.tscn
│   ├── panels/co_panel.tscn
│   ├── menus/action_menu.tscn        # Wait / Attack / Capture / Load / Join / Supply
│   ├── menus/build_menu.tscn
│   ├── menus/pause_menu.tscn
│   ├── screens/title.tscn
│   ├── screens/map_select.tscn
│   ├── screens/co_select.tscn
│   ├── screens/results.tscn
│   └── screens/options.tscn
│
├── persistence/
│   ├── save_game.gd                 # initial state + action log
│   ├── replay.gd
│   └── settings.gd
│
├── tools/
│   ├── map_editor/map_editor.tscn   # @tool or standalone in-game editor
│   └── ci/check_core_purity.gd      # lint: fails build if core/ touches Node
│
├── autoload/
│   ├── audio_director.gd
│   ├── scene_router.gd
│   └── settings_store.gd
│
└── tests/
    ├── unit/                        # per-module rules tests
    ├── property/                    # invariant fuzzing
    ├── golden/                      # AI behavior regression
    └── fixtures/                    # small deterministic maps
```

---

## 3. Core state model

### `GameState`

The root aggregate. Everything needed to reconstruct the game exactly.

```gdscript
class_name GameState
extends RefCounted

var ruleset: Ruleset                        # data, not owned
var config: GameConfig
var map: MapState
var units: Dictionary[int, UnitState] = {}  # id -> unit
var occupancy: Dictionary[Vector2i, int] = {}  # coord -> unit id (derived, kept in sync)
var players: Array[PlayerState] = []
var current_player: int = 0
var day: int = 1
var weather: int = Weather.CLEAR
var weather_days_left: int = 0
var rng: DeterministicRng
var next_unit_id: int = 1

func clone() -> GameState                   # deep copy — needed for AI search
func unit_at(coord: Vector2i) -> UnitState  # null if empty
func units_of(team: int) -> Array[UnitState]
func active_player() -> PlayerState
```

Keep `occupancy` as a derived index, rebuilt on load and maintained on every move. It turns "who is on this tile" from O(n) into O(1), which matters once the AI is doing thousands of lookups per turn.

### `MapState`

```gdscript
class_name MapState
extends RefCounted

var width: int
var height: int
var terrain: PackedInt32Array               # w*h, index into ruleset.terrain_types
var property_owner: PackedInt32Array        # w*h, team id or -1
var capture_progress: Dictionary[Vector2i, int] = {}   # sparse — only in-progress tiles

func idx(c: Vector2i) -> int:  return c.y * width + c.x
func in_bounds(c: Vector2i) -> bool
func terrain_at(c: Vector2i) -> int
func is_property(c: Vector2i) -> bool
```

`PackedInt32Array` is copy-on-write and value-typed — cheap to clone for AI search, and immune to the aliasing bug that reference-typed `Array` invites.

### `UnitState`

```gdscript
class_name UnitState
extends RefCounted

var id: int
var type_id: int                # index into ruleset.unit_types
var team: int
var coord: Vector2i
var hp: int = 100               # internal 1..100
var fuel: int
var ammo: int
var has_moved: bool = false
var has_acted: bool = false     # exhausted this turn
var cargo: Array[int] = []      # unit ids being transported
var carrier_id: int = -1        # -1 if not loaded

func display_hp() -> int:  return int(ceil(hp / 10.0))   # 1..10
```

**Internal HP 0–100, displayed 1–10.** This is not cosmetic — Advance Wars scales attack output and terrain defense by *displayed* HP while tracking damage at finer granularity, and repair/join math depends on the internal value. Getting this wrong makes every combat number subtly off. Encode it once, here, and never let the presentation layer see raw `hp`.

### `PlayerState`

```gdscript
class_name PlayerState
extends RefCounted

var team: int
var funds: int = 0
var co_id: int = -1
var power_meter: int = 0
var power_state: int = PowerState.NONE   # NONE / CO_POWER / SUPER
var power_turns_left: int = 0
var is_alive: bool = true
var is_ai: bool = false
```

---

## 4. Actions

An Advance Wars turn is a sequence of atomic unit actions. The critical design point: **a move and its terminal verb are one Action, not two.** A unit that moves and then attacks did one thing. Splitting them makes undo, replay, and AI search all harder.

```gdscript
class_name UnitAction
extends Action

enum Verb { WAIT, ATTACK, CAPTURE, LOAD, UNLOAD, SUPPLY, JOIN, LAUNCH, REPAIR }

var unit_id: int
var path: Array[Vector2i] = []      # full path incl. start; last element is destination
var verb: int = Verb.WAIT
var target_coord: Vector2i          # attack target, unload destination
var cargo_index: int = -1           # which passenger, for UNLOAD
```

Other actions:

```gdscript
class_name BuildAction    # unit_type_id, coord (must be own unoccupied factory/port/airport)
class_name PowerAction    # power_level: CO_POWER | SUPER_CO_POWER
class_name EndTurnAction  # no fields
```

**Why the full path and not just a destination:** fog of war. In AW, a unit moving through fog can be stopped mid-path by an ambush. The rules layer needs the intended path to know where the interruption happens. It also lets the renderer draw the exact arrow the player traced.

### The front door

```gdscript
class_name Rules

## null when legal; otherwise a reason code the UI can display.
static func validate(state: GameState, action: Action) -> ActionError

## Mutates `state` in place and returns the ordered event log.
## Precondition: validate() returned null.
static func apply(state: GameState, action: Action) -> Array[GameEvent]
```

**A note on mutate-vs-return.** A pure `apply(state, action) -> GameState` is architecturally cleaner, but GDScript has no persistent data structures and cloning the whole state on every action is wasteful once the AI is searching. The pragmatic compromise: `apply()` mutates, and callers who need the old state call `state.clone()` first. AI search clones at the branch point. Undo replays from a turn-start snapshot. Document this and hold the line — half-mutating functions are how state corruption gets in.

---

## 5. Events

The core's output language. Presentation consumes these; it never inspects state diffs.

```gdscript
class_name GameEvent extends RefCounted

# Concrete types
UnitMoved          { unit_id, path: Array[Vector2i], interrupted_at: int }
UnitAmbushed       { unit_id, by_unit_id, coord }
UnitAttacked       { attacker_id, defender_id, damage, ammo_used }
UnitCounterattacked{ attacker_id, defender_id, damage }
UnitDestroyed      { unit_id, coord }
UnitCreated        { unit_id, type_id, team, coord }
UnitLoaded         { unit_id, carrier_id }
UnitUnloaded       { unit_id, carrier_id, coord }
UnitJoined         { survivor_id, absorbed_id, new_hp, funds_refund }
UnitResupplied     { unit_id, fuel, ammo }
UnitRepaired       { unit_id, hp_restored, cost }
UnitExhausted      { unit_id }
CaptureProgressed  { coord, unit_id, points, total }
PropertyCaptured   { coord, new_team, old_team }
FundsChanged       { team, delta, new_total, reason }
PowerCharged       { team, delta, new_total }
PowerActivated     { team, level, co_id }
PowerExpired       { team }
WeatherChanged     { new_weather, days }
TurnStarted        { team, day }
TurnEnded          { team }
PlayerEliminated   { team, reason }
GameEnded          { winning_team, reason }
```

This list is the actual contract between your core and everything else. Getting it right early is worth more than getting any single rule right, because it's what lets the animation layer, the audio layer, the AI's opponent-modeling, and a future network layer all be written independently.

---

## 6. Rules modules

### `Movement`

```gdscript
class_name Movement

## Bounded Dijkstra. Returns coord -> remaining movement points.
static func reachable(state: GameState, unit_id: int) -> Dictionary[Vector2i, int]

## Cost for this unit's movement class to enter `coord`. -1 if impassable.
static func enter_cost(state: GameState, unit: UnitState, coord: Vector2i) -> int

## Cheapest path between two reachable coords, for cursor path preview.
static func path_to(state: GameState, unit_id: int, dest: Vector2i) -> Array[Vector2i]

## Validates a client-supplied path — contiguous, affordable, no illegal tiles.
static func validate_path(state: GameState, unit_id: int, path: Array[Vector2i]) -> bool
```

Blocking rules to encode: enemy units block movement entirely (and are invisible blockers in fog — a unit stops when it bumps one). Allied units are passable but not stoppable-on. Fuel caps effective movement independently of movement points — fuel is spent per tile entered, one per step, while movement points pay terrain cost. Weather modifies costs by movement class.

Reachable-set size on a 30×20 map with movement 9 is at most a few hundred tiles — a plain `Dictionary` + sorted-array frontier is fast enough. Don't build a binary heap until profiling says so.

### `Combat`

```gdscript
class_name Combat

class DamagePreview:
    var damage: int              # internal HP points
    var damage_display: float    # for the UI, e.g. 5.5
    var counter_damage: int
    var can_counter: bool
    var has_ammo: bool

static func preview(state: GameState, attacker_id: int, defender_id: int) -> DamagePreview
static func resolve(state: GameState, attacker_id: int, defender_id: int) -> Array[GameEvent]
static func attackable_tiles(state: GameState, unit_id: int, from: Vector2i) -> Array[Vector2i]
```

The damage formula has this shape:

```
base       = damage_table[attacker_type][defender_type]   # by weapon, primary or secondary
attack_mod = 100 + co_attack_bonus + power_bonus
defense_mod= 100 + co_defense_bonus + power_bonus
terrain    = terrain_stars(defender_tile) × defender.display_hp()

damage = base
       × (attacker.display_hp() / 10.0)
       × (attack_mod / 100.0)
       × ((200 - defense_mod - terrain) / 100.0)
       + luck_roll(state.rng)
```

⚠️ **Pin the exact coefficients from a community reference before balancing.** They differ between AW1, AW2, Dual Strike, and Days of Ruin — particularly the luck range and how defense stacks. Put the whole thing behind `Ruleset` so switching variants is a data change, and write the formula as one function you can unit-test against a table of known-good values scraped from a damage calculator.

Rules to encode: direct-combat units counterattack, indirect (ranged) units never do; indirects can't move and fire in the same action; counterattack damage uses the defender's *post-damage* HP; a unit with no ammo falls back to its secondary weapon or can't attack at all.

**The luck roll is why `DeterministicRng` lives in `GameState`.** If the RNG is global or unseeded, replays desync and golden-file AI tests are useless. Seed it from the match seed, advance it only inside `apply()`, and never call it from presentation.

### `Fog`

```gdscript
class_name Fog

## Bitmask per tile, one bit per team. Recomputed at turn start and after each move.
static func compute(state: GameState, team: int) -> PackedByteArray

## Fog-filtered projection — what this team is allowed to know.
static func project(state: GameState, team: int) -> StateView
```

`StateView` is important. The AI and the UI should both consume a **fog-filtered view**, not raw `GameState`. If the AI reads `GameState` directly it cheats, and you won't notice until someone complains that hard mode sees through fog. Make cheating require a deliberate flag rather than being the default.

Rules: vision is per-unit radius plus owned properties; forests and reefs hide units unless adjacent; recon-type units have extended vision; some COs modify vision.

### `TurnFlow`

```gdscript
class_name TurnFlow

## Income, repair on matching properties, fuel drain, crash checks,
## capture reset for units that moved, power meter, weather roll, unit un-exhaust.
static func begin_turn(state: GameState, team: int) -> Array[GameEvent]
static func end_turn(state: GameState) -> Array[GameEvent]
```

The start-of-turn sequence has a specific order that matters: income before repair (repairs cost funds), repair before fuel drain, fuel drain before crash checks. Write it once, test it explicitly, and never let it get inlined into `apply()`.

### `ActionGenerator`

```gdscript
class_name ActionGenerator

## Every legal action for the current player. Used by the AI for search
## and by the UI to decide which action-menu entries to show.
static func generate(state: GameState) -> Array[Action]
static func for_unit(state: GameState, unit_id: int) -> Array[Action]
static func verbs_at(state: GameState, unit_id: int, dest: Vector2i) -> Array[int]
```

**This module is the highest-leverage thing in the codebase.** One implementation of "what's legal" drives the action menu, the AI, and the tutorial hint system. The alternative — the UI deciding what to show and the rules separately deciding what's legal — guarantees the two drift, which is the single most common source of tactics-game bugs.

---

## 7. Data resources

`Ruleset` is the balance root — one `.tres` that references everything else. Swapping it swaps the entire game's balance.

```gdscript
class_name Ruleset extends Resource

@export var unit_types: Array[UnitType] = []
@export var terrain_types: Array[TerrainType] = []
@export var movement_classes: Array[MovementClass] = []
@export var cos: Array[COProfile] = []
@export var damage_tables: Array[DamageTable] = []
@export var starting_funds: int = 0
@export var funds_per_property: int = 1000
@export var luck_max: int = 9
@export var capture_threshold: int = 20
@export var repair_hp_per_turn: int = 20        # internal HP
@export var max_units_per_player: int = 50
```

```gdscript
class_name UnitType extends Resource

@export var key: StringName = &""               # stable id for save files
@export var display_name: String = ""
@export var sprite_frames: SpriteFrames
@export var cost: int = 1000
@export var movement: int = 3
@export var movement_class: MovementClass
@export var vision: int = 2
@export var max_fuel: int = 99
@export var fuel_per_turn: int = 0              # daily drain (air/sea units)
@export var crashes_without_fuel: bool = false
@export var primary_weapon: WeaponProfile
@export var secondary_weapon: WeaponProfile
@export var max_ammo: int = 0
@export_range(0, 5) var attack_range_min: int = 1
@export_range(0, 8) var attack_range_max: int = 1
@export var can_move_and_fire: bool = true
@export var capture_capable: bool = false
@export var supply_capable: bool = false
@export var transport_capacity: int = 0
@export var transportable_classes: Array[MovementClass] = []
@export var built_at: Array[StringName] = []    # &"factory", &"port", &"airport"
```

```gdscript
class_name TerrainType extends Resource

@export var key: StringName = &""
@export var display_name: String = ""
@export_range(0, 4) var defense_stars: int = 0
@export var is_property: bool = false
@export var capturable: bool = false
@export var income: int = 0
@export var repairs_classes: Array[MovementClass] = []
@export var builds: StringName = &""            # non-empty if a production facility
@export var hides_units: bool = false           # forest / reef
@export var vision_bonus: int = 0               # mountains
## Movement cost per movement class per weather. -1 = impassable.
@export var move_costs: Dictionary[StringName, PackedInt32Array] = {}
```

Store `move_costs` keyed by movement-class `key` with one entry per weather condition. That single dictionary replaces what would otherwise be a sprawling `if unit is Tank and weather == Snow` mess, and it's editable in the inspector by someone who isn't you.

**Use `key: StringName` as the stable identifier in save files, not array index.** Indices shift when you reorder units in the ruleset, silently corrupting every existing save.

---

## 8. Presentation layer

### `BattleController` — the input state machine

```
                ┌──────────────────────────────────┐
                ▼                                  │
  ┌──────────► IDLE ──select own unit──► UNIT_SELECTED
  │             │                             │
  │             │ select own factory          │ move cursor within range
  │             ▼                             ▼
  │         BUILD_MENU               CHOOSING_DESTINATION
  │             │                             │ confirm
  │             │ confirm                     ▼
  │             │                        ACTION_MENU ──cancel──► UNIT_SELECTED
  │             │                             │
  │             │              ┌──────────────┼──────────────┐
  │             │           attack        unload/other      wait
  │             │              ▼              ▼              │
  │             │        TARGET_SELECT   TARGET_SELECT       │
  │             │              │              │              │
  │             └──────────────┴──────────────┴──────────────┘
  │                                    │ commit
  │                                    ▼
  │                              EXECUTING  ── Rules.apply() ──► EventPlayer
  │                                    │
  └────────────────────────────────────┘

  Separate branches: ENEMY_TURN (AI thinking + animating), MENU (pause), GAME_OVER
```

**Nothing is committed until the final confirm.** Every cancel before that is pure controller state — no core call, no undo machinery. This is exactly how Advance Wars feels, and it falls out for free from the "move + verb is one atomic Action" decision.

```gdscript
class_name BattleController
extends Node

enum State { IDLE, UNIT_SELECTED, CHOOSING_DESTINATION, ACTION_MENU,
             TARGET_SELECT, BUILD_MENU, EXECUTING, ENEMY_TURN, GAME_OVER }

var _state: GameState
var _phase: State = State.IDLE
var _selected_unit_id: int = -1
var _reachable: Dictionary[Vector2i, int] = {}
var _current_path: Array[Vector2i] = []

func _commit(action: Action) -> void:
    var err := Rules.validate(_state, action)
    if err != null:
        _hud.show_error(err)
        return
    _phase = State.EXECUTING
    var events := Rules.apply(_state, action)
    await _event_player.play(events)      # animation coroutine
    _phase = State.IDLE
```

### `EventPlayer`

Translates the event log into animation, sequentially, with `await`. This is where GDScript coroutines genuinely beat a C++ callback architecture.

```gdscript
func play(events: Array[GameEvent]) -> void:
    for e in events:
        match e.get_script():
            UnitMoved:       await _animate_move(e)
            UnitAttacked:    await _animate_attack(e)
            UnitDestroyed:   await _animate_death(e)
            PropertyCaptured: await _animate_capture(e)
            _:               _apply_instantly(e)
```

Add a global animation-speed setting and a skip toggle here, once, and every animation in the game respects it.

### Rendering nodes

| Node | Responsibility |
|---|---|
| `MapRenderer` | Two `TileMapLayer`s (terrain, property overlay). Re-tints properties on ownership change. |
| `UnitLayer` | Pools `UnitView` instances keyed by unit id. Creates/frees on `UnitCreated`/`UnitDestroyed`. |
| `UnitView` | Sprite, team palette, HP pip, low-ammo/low-fuel/capture icons, greyed-out when exhausted. |
| `OverlayLayer` | `_draw()` for move range (blue), attack range (red), path arrow. Redrawn only on selection change. |
| `FogLayer` | Darkened tiles from the fog bitmask. |
| `Cursor` | Grid-snapped, keyboard + mouse + touch. Drives the info panels on move. |
| `CameraRig` | Follows cursor with a dead zone, clamps to map bounds, smooth pan to action during enemy turns. |

Keep the terrain grid authoritative in `MapState` and treat `TileMapLayer` as a pure view. The renderer reads state; state never reads the renderer.

---

## 9. UI inventory

| Screen / panel | Notes |
|---|---|
| Terrain info panel | Terrain name, defense stars, capture progress. Follows cursor. |
| Unit info panel | Type, HP, fuel, ammo, cargo. Shown when cursor is over a unit. |
| Damage preview | Predicted damage + counter, shown during `TARGET_SELECT`. Non-negotiable for playability. |
| Action menu | Contextual verbs from `ActionGenerator.verbs_at()`. |
| Build menu | Unit list filtered by facility type and affordability, with cost and funds remaining. |
| CO panel | Portrait, power meter, active power indicator. |
| Turn banner | "Orange Star — Day 4" transition. |
| Pause menu | End turn, options, surrender, quit. |
| Title / map select / CO select / results | Standard flow. |
| Options | Animation speed, audio, controls, fog toggle. |

Build the `Theme` resource before styling anything. Retrofitting a theme across forty hand-styled controls is the kind of task that kills side projects.

---

## 10. AI

```gdscript
class_name AIPlayer
extends RefCounted

## Given a fog-filtered view, return the next action. Called repeatedly
## until it returns EndTurnAction.
func choose_action(view: StateView) -> Action
```

Build it in three stages, and don't skip to stage three:

**Stage 1 — greedy, one unit at a time.** For each unexhausted unit, enumerate legal actions, score each with a hand-weighted heuristic (damage dealt, damage taken next turn, capture progress, distance to nearest objective), take the best. Plays a recognizable game of Advance Wars and is maybe 300 lines. This gets you a playable game months earlier than anything cleverer.

**Stage 2 — add maps.** A `ThreatMap` (damage each tile would take if occupied) and an `InfluenceMap` (territory control) turn the scoring from "attack whatever's adjacent" into something that positions sensibly and retreats damaged units.

**Stage 3 — search, if needed.** Full-turn lookahead has a brutal branching factor: 15 units × ~200 reachable tiles × ~4 verbs is ~10⁴ per unit and the turn is a permutation of all of them. Realistic approaches are unit-ordered greedy with limited rollout, or Monte Carlo over the top-k candidate action sequences. Time-slice with a coroutine so the main thread stays responsive; only reach for `WorkerThreadPool` if profiling demands it, and remember the web-export threading caveat.

`AIProfile` as a Resource gives you difficulty levels as data — aggression, risk tolerance, build preferences, whether it uses CO powers optimally — without branching code.

---

## 11. Save, replay, undo

Because state is `initial_state + ordered action list`, all three are the same feature.

```gdscript
class_name SaveGame extends RefCounted

var version: int
var ruleset_key: StringName
var map_key: StringName
var rng_seed: int
var player_setup: Array          # teams, COs, human/AI
var action_log: Array[Dictionary]   # serialized actions

func to_json() -> String
static func from_json(s: String) -> SaveGame
static func replay(save: SaveGame) -> GameState    # deterministic reconstruction
```

Save files are tiny and human-readable, replays are free, and desyncs become detectable — which is what makes networked multiplayer tractable later if you want it.

**Undo:** snapshot `GameState.clone()` at turn start, pop the last action, replay the rest. ⚠️ With fog of war this leaks information — undoing a move that revealed an enemy lets you keep the knowledge. Either disable undo in fog matches or restrict it to actions that revealed nothing. Decide this early; it affects the UI.

Guard `version` and reject mismatches loudly. A save format that silently half-loads is worse than one that refuses.

---

## 12. Testing plan

| Layer | Approach |
|---|---|
| `Movement` | Fixture maps with hand-computed reachable sets. Every movement class × every terrain × every weather. |
| `Combat` | Table-driven against known-good damage values, luck disabled via fixed seed. |
| `Capture`/`Supply`/`Economy` | Direct unit tests on small fixtures. |
| `TurnFlow` | Explicit ordering assertions — income before repair, repair before fuel. |
| `Fog` | Symmetry and monotonicity properties; regression tests for forest/reef hiding. |
| `Rules.apply` | Property tests: generate random legal sequences, assert invariants after each. |
| `ActionGenerator` | Every generated action must pass `validate()`. Every action passing `validate()` in a fixture must be generated. |
| AI | Golden-file: fixed map + fixed seed → stable action sequence. Catches behavior drift. |
| Determinism | Replay a serialized log twice, assert identical final state hashes. |

Invariants worth asserting after every action:

- Unit count is conserved except across explicit destroy/create events
- `occupancy` agrees with `units`
- No two units share a coord
- All HP in 1..100, fuel and ammo within type maxima
- Every loaded unit's `carrier_id` points at a carrier whose `cargo` contains it
- Funds never negative
- The event log, replayed against a clone of the pre-state, reproduces the post-state

That last one is the strongest test in the suite. It verifies the event log is a *complete* description of the state change, which is the property the entire presentation layer depends on.

CI: run headless on every push, plus the core-purity lint.

---

## 13. Build order

Each milestone is playable or verifiable on its own.

1. **Core skeleton, headless.** `GameState`, `MapState`, `UnitState`, `Movement.reachable()`. Tests + CI green. No rendering at all.
2. **Combat and turn flow.** `Combat`, `TurnFlow`, `Rules.apply()` with a WAIT/ATTACK verb set. Two units, one map, fully tested — still headless.
3. **Data layer.** `Ruleset` schema, four units, six terrain types authored as `.tres`.
4. **First render.** `MapRenderer`, `UnitLayer`, `Cursor`, `CameraRig`. Static display of a state.
5. **First playable loop.** `BattleController` + `OverlayLayer` + `EventPlayer`. Select, move, attack, end turn. **This is the milestone that matters** — everything before it is invisible, everything after it is iteration.
6. **Capture and economy.** Properties, income, factories, build menu. Now it's a game.
7. **Full unit roster and damage table.** Content work.
8. **Export everywhere.** Desktop, web, Android — while the project is still small.
9. **AI stage 1.** Greedy. Now it's single-player.
10. **UI pass.** Theme, panels, damage preview, transitions.
11. **Fog of war.** Touches everything; do it after the core is stable.
12. **Transports, supply, join, repair.** The remaining verbs.
13. **COs and powers.** The modifier hooks should already exist in `Combat` from step 2.
14. **Map editor**, save/replay, audio, polish.
15. **AI stages 2–3**, weather, campaign structure.

Steps 1–5 are the risky part. After a playable loop exists, the rest is additive and each piece is independently satisfying — which matters a lot for a solo project where stalling is the real failure mode.

---

## 14. Decisions to make before writing code

These are cheap to decide now and expensive to change later:

1. **Which Advance Wars?** AW2 and Days of Ruin have meaningfully different balance, CO systems, and damage tables. Pick one to clone faithfully; a hybrid means no reference to test against.
2. **Undo policy**, particularly under fog. Affects UI, save format, and whether you keep turn-start snapshots.
3. **CO powers in or out of v1.** They're a cross-cutting modifier system. If they're in, put the hooks in `Combat` and `Movement` from day one — retrofitting them is genuinely painful.
4. **Map size ceiling.** Affects whether naive algorithms are fine. Under 40×40, they are.
5. **Multiplayer ambitions.** The action-log design makes hotseat trivial and networked play tractable, but only if you never let presentation mutate state. Decide now whether you're holding that line.
6. **Art pipeline.** 16×16 or 32×32 tiles, team recoloring via palette swap shader or per-team sprite sheets. Palette swapping is far less asset work and worth setting up early.
```
