class_name Battle
extends Node2D
## Scene root: owns the match state, the render nodes, and (since the
## playable-loop milestone) the controller and event player. Builds a
## demo GameState on the classic ruleset until map loading exists.
## State is mutated only inside Rules.apply(), driven by the controller.
##
## battle.tscn is wired in the editor with this structure:
##   Battle (Node2D, battle.gd)
##   ├─ MapRenderer (Node2D, map_renderer.gd)
##   │  ├─ TerrainLayer (TileMapLayer)
##   │  ├─ DetailLayer (TileMapLayer — art mode: roads, trees, buildings)
##   │  └─ PropertyLayer (TileMapLayer)
##   ├─ OverlayLayer (Node2D, overlay_layer.gd)
##   ├─ UnitLayer (Node2D, unit_layer.gd)
##   ├─ Cursor (Node2D, cursor.gd)
##   ├─ CameraRig (Node2D at origin, camera_rig.gd)
##   │  └─ Camera2D (enabled)
##   ├─ EventPlayer (Node, event_player.gd)
##   ├─ BattleController (Node, battle_controller.gd)
##   └─ PointerInput (Node, pointer_input.gd)
## Exports to wire: Battle → its seven children plus classic.tres;
## MapRenderer → its three layers (+ an ArtSet); CameraRig → Camera2D + Cursor;
## EventPlayer → UnitLayer; BattleController → Cursor, OverlayLayer,
## UnitLayer, MapRenderer, EventPlayer; PointerInput → Cursor,
## BattleController, CameraRig.
## assemble() builds the same tree in code for tests and quick previews.
##
## Controls: arrows move the cursor, ui_accept (Enter/Space) selects,
## confirms destination, and picks targets; ui_cancel (Esc) steps back.
## +/- or the mouse wheel zooms. D toggles the enemy danger map;
## confirming an enemy unit inspects its ranges. Confirming an empty
## tile opens the system menu (powers, End Turn). Mouse and touch go
## through PointerInput: hover aims, click confirms, right-click
## cancels, drag pans.

## Emitted instead of restarting in place when hand_off_new_match is
## set: a finished match was acknowledged, or the player quit to the
## menu. main.gd answers with the match setup screen.
signal new_match_requested

const DEFAULT_ART_PATH := "res://assets/tiny_battle/tiny_battle.tres"
const DEMO_WIDTH := 10
const DEMO_HEIGHT := 8
## Terrain ids follow classic.tres order:
## 0 plains, 1 road, 2 forest, 3 mountain, 4 city, 5 factory.
const DEMO_TERRAIN: Array[int] = [
	0,
	0,
	2,
	0,
	0,
	0,
	0,
	2,
	0,
	0,
	0,
	4,
	2,
	0,
	3,
	3,
	0,
	2,
	4,
	0,
	0,
	5,
	0,
	0,
	3,
	0,
	0,
	0,
	5,
	0,
	1,
	1,
	1,
	1,
	1,
	1,
	1,
	1,
	1,
	1,
	0,
	0,
	0,
	2,
	0,
	0,
	2,
	0,
	0,
	0,
	0,
	4,
	0,
	2,
	0,
	0,
	2,
	0,
	4,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	0,
	2,
	0,
	0,
	0,
	0,
	2,
	0,
	0
]

@export var ruleset: Ruleset
@export var map_renderer: MapRenderer
@export var overlay: OverlayLayer
@export var unit_layer: UnitLayer
@export var cursor: Cursor
@export var camera_rig: CameraRig
@export var event_player: EventPlayer
@export var controller: BattleController
@export var pointer_input: PointerInput
@export var hud: Hud
@export var fog_layer: FogLayer

var state: GameState

## When true, play_again() and "Quit to menu" emit new_match_requested
## rather than restarting here.
## Where the match in progress is written after every action, and
## removed when it ends ("" = nowhere; main.gd sets it).
var autosave_path: String = ""
var hand_off_new_match: bool = false:
	set(value):
		hand_off_new_match = value
		if controller != null:
			controller.offer_quit = value

## The authored map the current match was started on; null for states
## loaded directly.
var _map_def: MapDefinition
## The match in progress as a save: its setup plus every action so far —
## which is also everything "play again" needs to start the same match
## afresh. Null for states loaded directly, which aren't recorded.
var _save: SaveGame


func _ready() -> void:
	_ensure_ruleset()
	# The demo is a fallback, not a default: a boot script may have
	# loaded a real match before we entered the tree (-s boots run
	# before any _ready fires).
	if state == null:
		load_state(build_demo_state(ruleset))


## Starts a plain match on an authored map — Normal difficulty, no head
## starts — with fog of war and random weather as asked. The short form
## of start_match(); _ready keeps the code-built demo so tests stay
## self-contained.
func load_map(def: MapDefinition, fog: bool = false, weather: bool = false) -> void:
	var options := MatchOptions.new()
	options.map = def
	options.fog = fog
	options.weather = weather
	start_match(options)


## Starts a match as `options` describe: Vale (human) vs Rook (AI) on the
## chosen map, each side with its starting funds, the AI at the chosen
## difficulty and with that level's income handicap.
func start_match(options: MatchOptions) -> void:
	_ensure_ruleset()  # callable before _ready (script boots)
	var level := AIProfileCatalog.find(options.difficulty)
	var save := SaveGame.new()
	save.map_key = options.map.key
	save.rng_seed = randi_seed_for_match()
	save.fog_enabled = options.fog
	save.weather_enabled = options.weather
	save.player_setup = [
		{"team": 0, "co": &"vale", "funds": options.player_funds},
		{
			"team": 1,
			"co": &"rook",
			"is_ai": true,
			"funds": options.enemy_funds,
			"income": level.income_percent,
			"ai": level.key,
		},
	]
	var gs := Replay.run(save, ruleset, options.map)
	if gs == null:
		push_warning("Battle: map %s failed to build; keeping current state" % options.map.key)
		return
	_begin(options.map, save, gs)
	_autosave()


## Picks a saved match back up: replays its log on its map and carries on
## recording into it. False (changing nothing) when the save can't be
## replayed here — an unknown map, or rules that no longer agree with it.
func resume(save: SaveGame) -> bool:
	_ensure_ruleset()
	var def := MapCatalog.find(save.map_key)
	if def == null:
		return false
	var gs := Replay.run(save, ruleset, def)
	if gs == null:
		return false
	_begin(def, save, gs)
	return true


## Binds a match that has a map and a save behind it. The save is in
## place before the controller sees the state: an AI that is to move
## starts at once, and its actions must be recorded.
func _begin(def: MapDefinition, save: SaveGame, gs: GameState) -> void:
	_map_def = def
	_save = save
	if controller != null:
		controller.use_ai_profile(AIProfileCatalog.find(_ai_level(save)))
	_bind(gs)


## The difficulty key a save's AI player carries (Normal when it has
## none: saves from before difficulty levels).
static func _ai_level(save: SaveGame) -> StringName:
	for entry: Dictionary in save.player_setup:
		if entry.get("is_ai", false) and entry.has("ai"):
			return entry["ai"]
	return &"normal"


## Falls back to the classic ruleset when none was wired in the editor.
func _ensure_ruleset() -> void:
	if ruleset == null:
		ruleset = load("res://data/rulesets/classic.tres") as Ruleset


## Match seeds come from the OS clock at match start — the one moment
## randomness may enter from outside DeterministicRng; the seed is then
## recorded so replays reproduce everything.
func randi_seed_for_match() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) % 1000000000


## Presents `gs` and rebinds the controller and event player to it —
## the single entry point for demo, tests, and future save loading.
func load_state(gs: GameState) -> void:
	_map_def = null
	_save = null
	if controller != null:
		controller.use_ai_profile(AIProfile.new())
	_bind(gs)


func _bind(gs: GameState) -> void:
	state = gs
	present(gs)
	if event_player != null:
		event_player.setup(gs)
	if controller != null:
		if not controller.restart_requested.is_connected(play_again):
			controller.restart_requested.connect(play_again)
			controller.quit_requested.connect(_on_quit_requested)
			controller.action_committed.connect(_on_action_committed)
		controller.offer_quit = hand_off_new_match
		controller.setup(gs)


## Starts a new match after one ends: hands off to whoever listens when
## hand_off_new_match is set; otherwise a fresh seed on the same authored
## map with the same options, or the demo when the finished state wasn't
## built from a map.
func play_again() -> void:
	if hand_off_new_match:
		new_match_requested.emit()
		return
	if _map_def != null and _save != null:
		var fresh := SaveGame.new()
		fresh.map_key = _save.map_key
		fresh.rng_seed = randi_seed_for_match()
		fresh.fog_enabled = _save.fog_enabled
		fresh.weather_enabled = _save.weather_enabled
		fresh.player_setup = _save.player_setup.duplicate(true)
		var gs := Replay.run(fresh, ruleset, _map_def)
		if gs != null:
			_begin(_map_def, fresh, gs)
			_autosave()
		return
	_ensure_ruleset()
	load_state(build_demo_state(ruleset))


## Records each applied action; the autosave follows it, and is removed
## once the match is decided (there is nothing left to continue).
func _on_action_committed(action: Action, events: Array[GameEvent]) -> void:
	if _save == null:
		return
	_save.record(action, ruleset)
	_save.digest = Replay.digest(state)
	for e: GameEvent in events:
		if e is Events.GameEnded:
			if autosave_path != "":
				SaveGame.delete_file(autosave_path)
			return
	_autosave()


func _autosave() -> void:
	if autosave_path != "" and _save != null:
		_save.write_file(autosave_path)


func _on_quit_requested() -> void:
	if hand_off_new_match:
		new_match_requested.emit()


## Pushes a full state into every render node.
func present(gs: GameState) -> void:
	if map_renderer == null or unit_layer == null or cursor == null or camera_rig == null:
		push_warning("Battle: render nodes not wired; check battle.tscn exports")
		return
	map_renderer.render(gs)
	unit_layer.sync(gs)
	cursor.set_map(gs.map.width, gs.map.height)
	camera_rig.set_map(gs.map.width, gs.map.height)
	@warning_ignore("integer_division")
	var center := Vector2i(gs.map.width / 2, gs.map.height / 2)
	cursor.move_to(center)
	camera_rig.center_on(center)


## The art pack the shipped game draws with, or null if it's missing (the
## flat-color placeholders then draw everything).
static func default_art() -> ArtSet:
	if not ResourceLoader.exists(DEFAULT_ART_PATH):
		return null
	return load(DEFAULT_ART_PATH) as ArtSet


## The whole battle tree built in code — used by the shipped boot
## (main.gd), tools/preview_battle.gd, and headless tests. `art` is the
## sprite sheet to draw with; null (the tests' default) keeps the
## flat-color placeholders.
static func assemble(art: ArtSet = null) -> Battle:
	var battle := Battle.new()
	battle.name = "Battle"
	var renderer := MapRenderer.new()
	renderer.name = "MapRenderer"
	var terrain := TileMapLayer.new()
	terrain.name = "TerrainLayer"
	var details := TileMapLayer.new()
	details.name = "DetailLayer"
	var property_overlay := TileMapLayer.new()
	property_overlay.name = "PropertyLayer"
	renderer.add_child(terrain)
	renderer.add_child(details)
	renderer.add_child(property_overlay)
	renderer.terrain_layer = terrain
	renderer.detail_layer = details
	renderer.property_layer = property_overlay
	renderer.art_set = art
	var ranges := OverlayLayer.new()
	ranges.name = "OverlayLayer"
	ranges.art_set = art
	var units := UnitLayer.new()
	units.name = "UnitLayer"
	units.art_set = art
	var shroud := FogLayer.new()
	shroud.name = "FogLayer"
	var cur := Cursor.new()
	cur.name = "Cursor"
	cur.art_set = art
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	var cam := Camera2D.new()
	rig.add_child(cam)
	rig.camera = cam
	rig.cursor = cur
	var player := EventPlayer.new()
	player.name = "EventPlayer"
	player.unit_layer = units
	var control := BattleController.new()
	control.name = "BattleController"
	control.cursor = cur
	control.overlay = ranges
	control.unit_layer = units
	control.map_renderer = renderer
	control.event_player = player
	var ui := Hud.new()
	ui.name = "Hud"
	control.hud = ui
	control.fog_layer = shroud
	battle.add_child(renderer)
	battle.add_child(ranges)
	battle.add_child(units)
	battle.add_child(shroud)
	battle.add_child(cur)
	battle.add_child(rig)
	battle.add_child(player)
	battle.add_child(control)
	var pointer := PointerInput.new()
	pointer.name = "PointerInput"
	pointer.cursor = cur
	pointer.controller = control
	pointer.camera_rig = rig
	battle.add_child(pointer)
	battle.add_child(ui)
	battle.map_renderer = renderer
	battle.overlay = ranges
	battle.unit_layer = units
	battle.fog_layer = shroud
	battle.cursor = cur
	battle.camera_rig = rig
	battle.event_player = player
	battle.controller = control
	battle.pointer_input = pointer
	battle.hud = ui
	return battle


## A small symmetric demo battle: four unit types per side, owned and
## neutral properties, one damaged and one exhausted unit so HP pips and
## the exhaustion tint are visible. Demo-only until MapDefinition exists.
static func build_demo_state(rs: Ruleset) -> GameState:
	var gs := GameState.new()
	gs.ruleset = rs
	gs.config = GameConfig.new()
	gs.map = _demo_map()
	gs.rng = DeterministicRng.new(42)
	for team: int in range(2):
		var p := PlayerState.new()
		p.team = team
		gs.players.append(p)
	gs.players[1].is_ai = true  # the demo opponent plays itself
	_claim(gs.map, Vector2i(1, 1), 0)
	_claim(gs.map, Vector2i(1, 2), 0)
	_claim(gs.map, Vector2i(8, 1), 1)
	_claim(gs.map, Vector2i(8, 2), 1)
	_spawn(gs, 5, 0, Vector2i(2, 3))
	var tired := _spawn(gs, 1, 0, Vector2i(1, 3))
	tired.has_acted = true
	_spawn(gs, 5, 0, Vector2i(3, 4))
	_spawn(gs, 5, 0, Vector2i(2, 5))
	var hurt := _spawn(gs, 0, 1, Vector2i(7, 3))
	hurt.hp = 55
	_spawn(gs, 1, 1, Vector2i(8, 3))
	_spawn(gs, 2, 1, Vector2i(6, 4))
	_spawn(gs, 3, 1, Vector2i(7, 5))
	return gs


static func _demo_map() -> MapState:
	var m := MapState.new()
	m.width = DEMO_WIDTH
	m.height = DEMO_HEIGHT
	var t := PackedInt32Array()
	t.resize(DEMO_TERRAIN.size())
	for i: int in range(DEMO_TERRAIN.size()):
		t[i] = DEMO_TERRAIN[i]
	m.terrain = t
	var owners := PackedInt32Array()
	owners.resize(DEMO_TERRAIN.size())
	owners.fill(MapState.NO_OWNER)
	m.property_owner = owners
	return m


static func _claim(map: MapState, coord: Vector2i, team: int) -> void:
	map.property_owner[map.idx(coord)] = team


static func _spawn(gs: GameState, type_id: int, team: int, coord: Vector2i) -> UnitState:
	var unit_type: UnitType = gs.ruleset.unit_types[type_id]
	var u := UnitState.new()
	u.id = gs.next_unit_id
	gs.next_unit_id += 1
	u.type_id = type_id
	u.team = team
	u.coord = coord
	u.fuel = unit_type.max_fuel
	u.ammo = unit_type.max_ammo
	gs.units[u.id] = u
	gs.occupancy[coord] = u.id
	return u
