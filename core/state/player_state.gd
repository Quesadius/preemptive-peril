class_name PlayerState
extends RefCounted
## Per-player funds, CO selection, and power-meter state.

## CO power activation state. Stays NONE until powers arrive in a later
## milestone, but the field exists from day one (architecture §3).
enum PowerState { NONE, CO_POWER, SUPER }

var team: int
var funds: int = 0
## Income collected each turn, as a percent of what the properties pay:
## 100 is the plain amount, 150 a half-again handicap bonus.
var income_percent: int = 100
var co_id: int = -1
var power_meter: int = 0
var power_state: int = PowerState.NONE
var power_turns_left: int = 0
var is_alive: bool = true
var is_ai: bool = false


## Deep copy.
func clone() -> PlayerState:
	var copy := PlayerState.new()
	copy.team = team
	copy.funds = funds
	copy.income_percent = income_percent
	copy.co_id = co_id
	copy.power_meter = power_meter
	copy.power_state = power_state
	copy.power_turns_left = power_turns_left
	copy.is_alive = is_alive
	copy.is_ai = is_ai
	return copy
