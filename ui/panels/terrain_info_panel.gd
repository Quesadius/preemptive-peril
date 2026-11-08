class_name TerrainInfoPanel
extends PanelContainer
## Terrain name, defense stars, ownership, and capture progress for the
## tile under the cursor (§9). Fed by Hud.inspect().

var _name_label: Label
var _detail_label: Label


func _init() -> void:
	var box := VBoxContainer.new()
	_name_label = Label.new()
	_detail_label = Label.new()
	box.add_child(_name_label)
	box.add_child(_detail_label)
	add_child(box)


## Refreshes the panel for `coord`. Capture progress on a tile
## `viewing_team` can't see would betray a hidden capturer, so it is
## shown only on visible tiles (-1 = omniscient).
func show_tile(state: GameState, coord: Vector2i, viewing_team: int = -1) -> void:
	var terrain: TerrainType = state.ruleset.terrain_types[state.map.terrain_at(coord)]
	_name_label.text = terrain.display_name
	var parts: Array[String] = ["DEF " + "*".repeat(terrain.defense_stars)]
	if terrain.capturable:
		var owner_team: int = state.map.property_owner[state.map.idx(coord)]
		parts.append("Neutral" if owner_team == MapState.NO_OWNER else "Team %d" % owner_team)
		var visible_tile: bool = viewing_team < 0 or Fog.tile_visible(state, viewing_team, coord)
		if visible_tile and state.map.capture_progress.has(coord):
			var progress: int = state.map.capture_progress[coord]
			parts.append("Capture %d/%d" % [progress, state.ruleset.capture_threshold])
	_detail_label.text = "  ".join(parts)


## The name line, for tests.
func name_text() -> String:
	return _name_label.text


## The detail line, for tests.
func detail_text() -> String:
	return _detail_label.text
