extends Node
## Autoload: central audio playout. Until sound assets exist this is the
## wiring only — play_sfx() resolves a stream from the registry (empty
## for now), honoring SettingsStore volumes. Presentation calls in via
## the autoload name and never touches AudioStreamPlayers directly.

## StringName -> AudioStream, filled when audio assets land.
var registry: Dictionary[StringName, AudioStream] = {}

var _player_pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for _i: int in range(4):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_player_pool.append(player)


## Plays a registered sound effect; unknown keys are silently skipped so
## presentation can wire calls before assets exist.
func play_sfx(key: StringName) -> void:
	if not registry.has(key):
		return
	for player: AudioStreamPlayer in _player_pool:
		if player.playing:
			continue
		player.stream = registry[key]
		player.volume_db = linear_to_db(_sfx_volume())
		player.play()
		return


func _sfx_volume() -> float:
	var store := get_node_or_null("/root/SettingsStore")
	if store == null:
		return 0.8
	return store.get_setting("sfx_volume")
