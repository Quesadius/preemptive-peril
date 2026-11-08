class_name AIPlayer
extends RefCounted
## Abstract AI (§10): given a fog-filtered view, return the next action.
## Called repeatedly until it returns EndTurnAction. Implementations must
## be deterministic — no RNG outside Rules.apply(), ties broken by
## generation order — or golden tests and replays fall apart.


## Override. The base class always ends the turn.
func choose_action(_view: StateView) -> Action:
	return EndTurnAction.new()
