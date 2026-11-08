class_name MapDefinition
extends Resource
## An authored map (§7). Terrain is stored as indices into this map's
## own `terrain_palette` of TerrainType keys — never into a ruleset
## array — so reordering the ruleset can't corrupt maps (CLAUDE.md).
## Starting units use type keys the same way.

@export var key: StringName = &""  # stable id for save files
@export var display_name: String = ""
@export var width: int = 10
@export var height: int = 10
## The terrain keys this map paints with.
@export var terrain_palette: Array[StringName] = []
## Row-major indices into terrain_palette, width * height entries.
@export var terrain: PackedInt32Array = PackedInt32Array()
## Row-major owning team per tile, or -1.
@export var property_owner: PackedInt32Array = PackedInt32Array()
## Starting units: {"type": StringName, "team": int, "x": int, "y": int}.
@export var starting_units: Array[Dictionary] = []
