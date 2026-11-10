class_name AIProfile
extends Resource
## Difficulty and personality as data (§10): what SimpleAI weighs and
## which of its habits are switched on, plus the handicap that goes with
## the level. The defaults are the Normal opponent; the shipped levels
## live under data/ai/ and are listed by AIProfileCatalog.

## Stable id, saved with a match so it resumes against the same opponent.
@export var key: StringName = &"normal"
@export var display_name: String = "Normal"
## One line for the new-match screen saying what the level means.
@export var description: String = ""
## Position in the difficulty list, easiest first.
@export var order: int = 1
## Handicap: the income this opponent collects, as a percent of what its
## properties pay (PlayerState.income_percent).
@export var income_percent: int = 100

## Scales the value of damage dealt.
@export var aggression: float = 1.0
## Scales the penalty for predicted counterattack damage.
@export var caution: float = 1.0
## Scales capture scoring.
@export var capture_weight: float = 1.0
## Scales the reward for closing distance to an objective.
@export var advance_weight: float = 1.0
## Scales the preference for pricier builds.
@export var expensive_unit_bias: float = 1.0

## Meets enemy capturers near its HQ: strikes them, or parks on the HQ.
@export var defends_hq: bool = true
## Builds an answer to enemy types nothing it owns can hurt.
@export var counter_builds: bool = true
## Advances into enemy range when its army isn't outgunned, instead of
## waiting just outside it.
@export var presses: bool = true
## Keeps at least this many capturers, and one per `capturer_share`
## units as the army grows (0 = no growth with army size).
@export var min_capturers: int = 2
@export var capturer_share: int = 8
