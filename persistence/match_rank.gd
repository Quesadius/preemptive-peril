class_name MatchRank
extends RefCounted
## Post-match S / A / B / C ranking across Speed, Power, and Technique
## (Advance Wars style). Pure computation from match stats tracked during play.

var days: int = 1
var par_days: int = 12
var best_turn_kills: int = 0
var units_built: int = 0
var units_lost: int = 0
var enemies_destroyed: int = 0

var speed_score: int = 100
var power_score: int = 100
var technique_score: int = 100
var total_score: int = 300
var grade: String = "S"


## Evaluates Speed, Power, Technique (0..100 each) and overall S/A/B/C grade.
static func evaluate(
	p_days: int,
	p_par_days: int,
	p_best_turn_kills: int,
	p_units_built: int,
	p_units_lost: int,
	p_enemies_destroyed: int
) -> MatchRank:
	var r := MatchRank.new()
	r.days = maxi(1, p_days)
	r.par_days = maxi(1, p_par_days)
	r.best_turn_kills = maxi(0, p_best_turn_kills)
	r.units_built = maxi(0, p_units_built)
	r.units_lost = maxi(0, p_units_lost)
	r.enemies_destroyed = maxi(0, p_enemies_destroyed)

	# Speed: 100 at or under par_days, -8 per extra day, floored at 20.
	var over: int = maxi(0, r.days - r.par_days)
	r.speed_score = clampi(100 - over * 8, 20, 100)

	# Power: biggest single-turn knockout burst (3+ kills in one turn = 100),
	# with fallback credit for fast HQ captures.
	if r.best_turn_kills >= 3:
		r.power_score = 100
	elif r.best_turn_kills == 2:
		r.power_score = 90
	elif r.best_turn_kills == 1:
		r.power_score = 75
	elif r.days <= 4:
		r.power_score = 85  # clean surgical HQ rush
	else:
		r.power_score = 55

	# Technique: survival ratio of fielded units (initial + built).
	var fielded: int = maxi(1, r.units_built + 4)
	var loss_ratio: float = float(r.units_lost) / float(fielded)
	r.technique_score = clampi(int(round(100.0 - loss_ratio * 90.0)), 20, 100)

	r.total_score = r.speed_score + r.power_score + r.technique_score
	if r.total_score >= 280:
		r.grade = "S"
	elif r.total_score >= 240:
		r.grade = "A"
	elif r.total_score >= 190:
		r.grade = "B"
	else:
		r.grade = "C"
	return r


## One-line summary for the victory panel.
func summary_text() -> String:
	return (
		"Rank %s (%d/300)\nSpeed %d  •  Power %d  •  Tech %d\nDay %d  •  Destroyed %d  •  Lost %d"
		% [
			grade,
			total_score,
			speed_score,
			power_score,
			technique_score,
			days,
			enemies_destroyed,
			units_lost,
		]
	)
