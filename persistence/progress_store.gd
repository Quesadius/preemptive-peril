class_name ProgressStore
extends RefCounted
## Saves and loads per-map / mission / puzzle completion records and best
## S/A/B/C ranks at user://progress.json.

const PATH := "user://progress.json"
const GRADE_ORDER: Dictionary[String, int] = {"C": 1, "B": 2, "A": 3, "S": 4}


## Reads the stored dictionary: key -> {"grade": String, "score": int, "days": int}.
static func load_all(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## Records a victory for `key`, keeping the highest grade/score and fastest day.
static func record_win(key: StringName, rank: MatchRank, path: String = PATH) -> void:
	var all: Dictionary = load_all(path)
	var k := String(key)
	var prev: Variant = all.get(k)
	var best_grade: String = rank.grade
	var best_score: int = rank.total_score
	var best_days: int = rank.days
	if prev is Dictionary:
		var pd: Dictionary = prev
		var old_grade: String = str(pd.get("grade", "C"))
		if GRADE_ORDER.get(old_grade, 0) > GRADE_ORDER.get(best_grade, 0):
			best_grade = old_grade
		best_score = maxi(best_score, int(pd.get("score", 0)))
		var old_days: int = int(pd.get("days", 999))
		if old_days > 0:
			best_days = mini(best_days, old_days)
	all[k] = {"grade": best_grade, "score": best_score, "days": best_days}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all, "\t"))
		file.close()


## Short badge text for a map/mission button, e.g. " [S]", or "" if unbeaten.
static func badge_for(key: StringName, records: Dictionary) -> String:
	var entry: Variant = records.get(String(key))
	if entry is Dictionary and (entry as Dictionary).has("grade"):
		return " [%s]" % str((entry as Dictionary)["grade"])
	return ""
