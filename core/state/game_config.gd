class_name GameConfig
extends RefCounted
## Match-level settings fixed before play begins: fog on/off, weather mode,
## rules variant (architecture §2).
##
## Immutable once the match starts — GameState.clone() shares the reference
## instead of copying.

var fog_enabled: bool = false
## When true, turn flow rolls the weather; when false it stays CLEAR.
var random_weather: bool = false
## Key of the ruleset variant this match uses (StringName, never an index).
var ruleset_key: StringName = &""
