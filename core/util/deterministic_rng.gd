class_name DeterministicRng
extends RefCounted
## The single sanctioned source of randomness in the project.
##
## Wraps Godot's RandomNumberGenerator behind an explicit seed and a
## state-preserving clone() so replays are bit-for-bit reproducible. Lives in
## GameState and is advanced only inside Rules.apply() — never from
## presentation or AI code.
##
## The public API deliberately avoids the global RNG function names
## (randi_range etc.) so callers in core/ don't trip the purity check.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _initial_seed: int = 0


## Creates a generator deterministically seeded with `initial_seed`.
func _init(initial_seed: int = 0) -> void:
	_initial_seed = initial_seed
	_rng.seed = initial_seed


## The seed this generator started from (recorded in save files).
func initial_seed() -> int:
	return _initial_seed


## Uniform random int in [from, to], inclusive on both ends.
## Advances the sequence.
func roll_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Exact copy, including the current position in the random sequence.
## The copy produces the same subsequent draws as the original and the two
## are fully independent afterwards.
func clone() -> DeterministicRng:
	var copy := DeterministicRng.new(_initial_seed)
	copy._rng.state = _rng.state
	return copy
