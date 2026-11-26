class_name MatchOptions
extends RefCounted
## What a new match is started with: the new-match screen fills one in,
## Battle.start_match() plays it. The defaults are a plain match — no
## fog, clear skies, the Normal opponent, nobody given a head start.

var map: MapDefinition
var fog: bool = false
var weather: bool = false
## AIProfile.key of the opponent's difficulty level.
var difficulty: StringName = &"normal"
## Starting funds for the player (team 0) and the opponent (team 1).
var player_funds: int = 0
var enemy_funds: int = 0
## COProfile keys for team 0 and team 1.
var player_co: StringName = &"vale"
var enemy_co: StringName = &"rook"
## When true, both teams are human-controlled (pass-and-play hotseat).
var hotseat: bool = false
## Puzzle turn limit (0 = unlimited).
var turn_limit: int = 0
## Par days for S-rank Speed scoring.
var par_days: int = 12
## Initial power meter for team 0 (used by tactical puzzles).
var initial_player_meter: int = 0
## Optional briefing flashed when the match begins (missions/puzzles).
var briefing: String = ""
## Key under which to save best rank in ProgressStore (defaults to map.key).
var record_key: StringName = &""
