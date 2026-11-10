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
## Starting funds for the player (team 0) and the computer (team 1).
var player_funds: int = 0
var enemy_funds: int = 0
