class_name MusicSynth
extends RefCounted
## Procedural chiptune tactical background music loops synthesized in code
## (matching SfxSynth: zero audio files, deterministic sample math).
## Keys: &"player_turn", &"enemy_turn", &"power".

const MIX_RATE := 22050


## Builds all looping background music AudioStreamWAVs.
static func build_all() -> Dictionary[StringName, AudioStream]:
	var out: Dictionary[StringName, AudioStream] = {}
	# Upbeat tactical march (C major, 16 eighth-notes = 2 bars @ 150 BPM -> 3.2s loop)
	out[&"player_turn"] = _build_loop(
		[
			523.25,
			0.0,
			659.25,
			783.99,
			659.25,
			587.33,
			523.25,
			392.00,
			440.00,
			523.25,
			587.33,
			659.25,
			587.33,
			0.0,
			392.00,
			493.88,
			523.25,
			0.0,
			659.25,
			783.99,
			880.00,
			783.99,
			659.25,
			523.25,
			587.33,
			659.25,
			587.33,
			493.88,
			523.25,
			0.0,
			523.25,
			0.0,
		],
		[
			130.81,
			130.81,
			196.00,
			196.00,
			130.81,
			130.81,
			196.00,
			196.00,
			174.61,
			174.61,
			146.83,
			146.83,
			196.00,
			196.00,
			196.00,
			146.83,
			130.81,
			130.81,
			196.00,
			196.00,
			220.00,
			220.00,
			164.81,
			164.81,
			146.83,
			146.83,
			196.00,
			196.00,
			130.81,
			196.00,
			130.81,
			0.0,
		],
		0.18
	)
	# Tense strategic enemy loop (A minor, steady stalking groove)
	out[&"enemy_turn"] = _build_loop(
		[
			440.00,
			0.0,
			523.25,
			493.88,
			440.00,
			0.0,
			329.63,
			0.0,
			349.23,
			0.0,
			440.00,
			392.00,
			329.63,
			0.0,
			293.66,
			329.63,
			440.00,
			523.25,
			587.33,
			523.25,
			493.88,
			440.00,
			392.00,
			329.63,
			349.23,
			329.63,
			293.66,
			329.63,
			220.00,
			0.0,
			220.00,
			0.0,
		],
		[
			110.00,
			0.0,
			110.00,
			164.81,
			110.00,
			0.0,
			164.81,
			130.81,
			116.54,
			0.0,
			116.54,
			174.61,
			164.81,
			0.0,
			146.83,
			164.81,
			110.00,
			0.0,
			146.83,
			130.81,
			123.47,
			110.00,
			196.00,
			164.81,
			174.61,
			164.81,
			146.83,
			164.81,
			110.00,
			164.81,
			110.00,
			0.0,
		],
		0.20
	)
	# High-energy CO Power heroic theme (D major, faster tempo!)
	out[&"power"] = _build_loop(
		[
			587.33,
			587.33,
			739.99,
			880.00,
			987.77,
			880.00,
			739.99,
			880.00,
			1174.66,
			0.0,
			987.77,
			880.00,
			739.99,
			880.00,
			659.25,
			0.0,
			587.33,
			739.99,
			880.00,
			1174.66,
			987.77,
			880.00,
			987.77,
			1174.66,
			1318.51,
			1174.66,
			987.77,
			880.00,
			1174.66,
			0.0,
			1174.66,
			0.0,
		],
		[
			146.83,
			220.00,
			146.83,
			220.00,
			196.00,
			293.66,
			196.00,
			220.00,
			146.83,
			220.00,
			196.00,
			220.00,
			164.81,
			220.00,
			164.81,
			220.00,
			146.83,
			220.00,
			146.83,
			220.00,
			196.00,
			246.94,
			196.00,
			293.66,
			220.00,
			220.00,
			196.00,
			220.00,
			146.83,
			220.00,
			146.83,
			220.00,
		],
		0.145
	)
	return out


static func _build_loop(lead: Array[float], bass: Array[float], step_secs: float) -> AudioStreamWAV:
	var steps: int = lead.size()
	var step_samples: int = int(step_secs * MIX_RATE)
	var total: int = steps * step_samples
	var pcm := PackedByteArray()
	pcm.resize(total * 2)
	var lead_phase: float = 0.0
	var bass_phase: float = 0.0
	for s: int in range(steps):
		var l_hz: float = lead[s]
		var b_hz: float = bass[s]
		var is_kick: bool = s % 4 == 0
		var is_hat: bool = s % 2 == 1
		for i: int in range(step_samples):
			var t: float = float(i) / float(step_samples)
			var sample: float = 0.0
			if l_hz > 0.0:
				lead_phase += l_hz / MIX_RATE
				var cyc: float = fposmod(lead_phase, 1.0)
				# Crisp 25% duty pulse wave for classic handheld tactics lead
				var sq: float = 1.0 if cyc < 0.25 else -1.0
				var env: float = minf(1.0, float(i) / 60.0) * (1.0 - t * 0.65)
				sample += sq * env * 0.14
			if b_hz > 0.0:
				bass_phase += b_hz / MIX_RATE
				var bcyc: float = fposmod(bass_phase, 1.0)
				var tri: float = 4.0 * absf(bcyc - 0.5) - 1.0
				var benv: float = minf(1.0, float(i) / 40.0) * (1.0 - t * 0.45)
				sample += tri * benv * 0.20
			if is_kick and t < 0.35:
				var kt: float = t / 0.35
				var k_env: float = (1.0 - kt) * (1.0 - kt)
				sample += sin(kt * TAU * 4.5) * k_env * 0.14
			elif is_hat and t < 0.14:
				var ht: float = t / 0.14
				var idx: int = s * step_samples + i
				var noise: float = fposmod(sin(float(idx) * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0
				sample += noise * (1.0 - ht) * 0.045
			var v: int = clampi(int(sample * 32767.0), -32768, 32767)
			var pos: int = (s * step_samples + i) * 2
			pcm[pos] = v & 0xFF
			pcm[pos + 1] = (v >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = total
	stream.data = pcm
	return stream
