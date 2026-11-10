class_name AIProfileCatalog
extends RefCounted
## The shipped difficulty levels under data/ai, for the new-match screen
## and for resolving a save's AI profile key back to its profile.

const PROFILE_DIR := "res://data/ai"


## Every shipped level, easiest first (AIProfile.order).
static func all() -> Array[AIProfile]:
	var profiles: Array[AIProfile] = []
	for file: String in ResourceLoader.list_directory(PROFILE_DIR):
		if not file.ends_with(".tres"):
			continue
		var profile := load(PROFILE_DIR.path_join(file)) as AIProfile
		if profile != null:
			profiles.append(profile)
	profiles.sort_custom(func(a: AIProfile, b: AIProfile) -> bool: return a.order < b.order)
	return profiles


## The level with this key; the plain Normal profile when there is none
## (a save from a build that had a level this one lacks still plays).
static func find(key: StringName) -> AIProfile:
	for profile: AIProfile in all():
		if profile.key == key:
			return profile
	return AIProfile.new()
