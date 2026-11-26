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
var music_registry: Dictionary[StringName, AudioStream] = {}

var _player_pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _current_track: StringName = &""


func _ready() -> void:
	if registry.is_empty():
		registry = SfxSynth.build_all()
	for _i: int in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_player_pool.append(player)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)


## Plays a looping synthesized music track (`&"player_turn"`, `&"enemy_turn"`,
## `"power"`). Safe to call repeatedly with the same track; respects both
## sound_on and music_on settings.
func play_music(track: StringName) -> void:
	_current_track = track
	if DisplayServer.get_name() == "headless":
		return
	if not _sound_on() or not _music_on():
		if _music_player != null:
			_music_player.stop()
		return
	if music_registry.is_empty():
		music_registry = MusicSynth.build_all()
	if not music_registry.has(track) or _music_player == null:
		return
	var target: AudioStream = music_registry[track]
	_music_player.volume_db = linear_to_db(_music_volume()) - 6.0
	if _music_player.stream != target or not _music_player.playing:
		_music_player.stream = target
		_music_player.play()


## Stops background music.
func stop_music() -> void:
	_current_track = &""
	if _music_player != null:
		_music_player.stop()


## Re-applies current sound/music settings to the active music player.
func refresh_music() -> void:
	if _current_track == &"":
		return
	play_music(_current_track)


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


func _music_on() -> bool:
	var store := get_node_or_null("/root/SettingsStore")
	if store == null:
		return true
	return store.get_setting("music_on")


func _music_volume() -> float:
	var store := get_node_or_null("/root/SettingsStore")
	if store == null:
		return 0.6
	return store.get_setting("music_volume")
