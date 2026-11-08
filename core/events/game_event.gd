class_name GameEvent
extends RefCounted
## Abstract base for the core's output language (§5). Rules.apply()
## returns an ordered Array[GameEvent]; presentation animates that list
## and never inspects state diffs. Concrete types live in events.gd as
## inner classes of Events.
