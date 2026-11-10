class_name SfxSynth
extends RefCounted
## The game's sound effects, synthesized in code: square and triangle
## blips, and noise bursts, shaped by a quick attack and a smooth decay.
## No audio files, so nothing to license or load. Noise is a fixed
## function of the sample index — no random numbers, the same samples
## on every run.
##
## Keys: select, cancel, move, attack, destroy, capture, captured, build,
## power, turn, victory, defeat.

enum Shape { SQUARE, TRIANGLE, NOISE }

const MIX_RATE := 22050
## Samples over which a tone fades in, to avoid a click.
const ATTACK_SAMPLES := 40.0

## Note frequencies (Hz) used by the jingles.
const C4 := 261.63
const E4 := 329.63
const G4 := 392.0
const C5 := 523.25
const E5 := 659.25
const G5 := 783.99
const C6 := 1046.5
const E_FLAT_4 := 311.13


## Every effect, keyed for AudioDirector's registry.
static func build_all() -> Dictionary[StringName, AudioStream]:
	var sq := Shape.SQUARE
	var tri := Shape.TRIANGLE
	var noise := Shape.NOISE
	var out: Dictionary[StringName, AudioStream] = {}
	out[&"select"] = _stream(_tone(660.0, 880.0, 0.06, sq, 0.22))
	out[&"cancel"] = _stream(_tone(440.0, 300.0, 0.08, sq, 0.2))
	out[&"move"] = _stream(
		_join([_tone(170.0, 150.0, 0.05, tri, 0.5), _tone(150.0, 130.0, 0.07, tri, 0.4)])
	)
	out[&"attack"] = _stream(
		_mix(_tone(0.0, 0.0, 0.18, noise, 0.35), _tone(140.0, 60.0, 0.18, tri, 0.4))
	)
	out[&"destroy"] = _stream(
		_mix(_tone(0.0, 0.0, 0.45, noise, 0.4), _tone(220.0, 40.0, 0.45, tri, 0.4))
	)
	out[&"capture"] = _stream(_join([_tone(C5, C5, 0.08, tri, 0.4), _tone(G5, G5, 0.12, tri, 0.4)]))
	out[&"captured"] = _stream(_notes([C5, E5, G5, C6], 0.09, tri, 0.4))
	out[&"build"] = _stream(_notes([G4, C5, E5], 0.07, sq, 0.2))
	out[&"power"] = _stream(_tone(220.0, 1320.0, 0.35, sq, 0.2))
	out[&"turn"] = _stream(_tone(880.0, 880.0, 0.16, tri, 0.3))
	out[&"victory"] = _stream(
		_join([_notes([C5, E5, G5], 0.11, sq, 0.22), _tone(C6, C6, 0.4, sq, 0.22)])
	)
	out[&"defeat"] = _stream(
		_join([_notes([G4, E_FLAT_4], 0.16, tri, 0.4), _tone(C4, C4, 0.45, tri, 0.4)])
	)
	return out


## One enveloped tone gliding from `from_hz` to `to_hz` (ignored for
## noise) over `seconds`, peaking at `level` (0..1).
static func _tone(
	from_hz: float, to_hz: float, seconds: float, shape: Shape, level: float
) -> PackedFloat32Array:
	var count: int = int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / count
		phase += lerpf(from_hz, to_hz, t) / MIX_RATE
		var cycle: float = fposmod(phase, 1.0)
		var v: float = 0.0
		match shape:
			Shape.SQUARE:
				v = 1.0 if cycle < 0.5 else -1.0
			Shape.TRIANGLE:
				v = 4.0 * absf(cycle - 0.5) - 1.0
			Shape.NOISE:
				v = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0
		var envelope: float = minf(1.0, i / ATTACK_SAMPLES) * (1.0 - t) * (1.0 - t)
		out[i] = v * envelope * level
	return out


## Equal-length notes one after another.
static func _notes(
	pitches: Array[float], seconds_each: float, shape: Shape, level: float
) -> PackedFloat32Array:
	var parts: Array[PackedFloat32Array] = []
	for hz: float in pitches:
		parts.append(_tone(hz, hz, seconds_each, shape, level))
	return _join(parts)


static func _join(parts: Array[PackedFloat32Array]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part: PackedFloat32Array in parts:
		out.append_array(part)
	return out


## Sums two sounds (the shorter one padded with silence).
static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), b.size()))
	for i: int in range(out.size()):
		var sum: float = 0.0
		if i < a.size():
			sum += a[i]
		if i < b.size():
			sum += b[i]
		out[i] = sum
	return out


## Packs samples (-1..1, clipped) as a 16-bit mono AudioStreamWAV.
static func _stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
