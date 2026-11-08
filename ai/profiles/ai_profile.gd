class_name AIProfile
extends Resource
## Difficulty and personality as data (§10): scoring weights consumed by
## SimpleAI. Defaults describe a balanced opponent; variants get
## authored as .tres when difficulty selection exists.

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
