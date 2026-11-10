extends Node
## Autoload: central audio playout. play_sfx() resolves a stream from the
## registry — filled at startup with SfxSynth's synthesized effects — and
## plays it on a free player, honoring the SettingsStore's sound switch
## and volume. Presentation calls in through Sfx.play() and never touches
## AudioStreamPlayers directly.

## A sound effect was asked for and will play if a player is free. Tests
## listen here; nothing else needs to.
signal sfx_requested(key: StringName)

const POOL_SIZE := 6

## StringName -> AudioStream.
var registry: Dictionary[StringName, AudioStream] = {}

var _player_pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	if registry.is_empty():
		registry = SfxSynth.build_all()
	for _i: int in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_player_pool.append(player)


## Plays a registered sound effect. Unknown keys and a switched-off sound
## setting are silently skipped; so is a moment when every player is
## busy (a burst of effects drops the excess rather than queueing it).
func play_sfx(key: StringName) -> void:
	if not registry.has(key) or not _sound_on():
		return
	sfx_requested.emit(key)
	for player: AudioStreamPlayer in _player_pool:
		if player.playing:
			continue
		player.stream = registry[key]
		player.volume_db = linear_to_db(_sfx_volume())
		player.play()
		return


func _sound_on() -> bool:
	var store := get_node_or_null("/root/SettingsStore")
	if store == null:
		return true
	return store.get_setting("sound_on")


func _sfx_volume() -> float:
	var store := get_node_or_null("/root/SettingsStore")
	if store == null:
		return 0.8
	return store.get_setting("sfx_volume")
