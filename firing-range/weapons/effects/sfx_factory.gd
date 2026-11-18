class_name SfxFactory
extends RefCounted
## Placeholder sound effects, synthesised in code at startup.
##
## Nothing here is recorded or sampled: each sound is built from seeded noise
## and sine tones, so the project has no audio files and stays text-only.
## Results are cached, so each sound is generated once.

const MIX_RATE: int = 22050

static var _cache: Dictionary[String, AudioStreamWAV] = {}


## A gunshot: a noise crack over a falling low thump. `pitch_hz` sets how
## heavy it sounds and `duration` how long the tail is.
static func gunshot(pitch_hz: float, duration: float) -> AudioStreamWAV:
	var key: String = "gunshot:%.1f:%.3f" % [pitch_hz, duration]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var count: int = int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	var smoothed: float = 0.0
	for index: int in count:
		var t: float = float(index) / float(MIX_RATE)
		var progress: float = t / duration
		# Crack: bright noise that dies in the first few milliseconds.
		var crack: float = rng.randf_range(-1.0, 1.0) * exp(-t * 55.0)
		# Body: low-passed noise with a longer tail.
		smoothed = lerpf(smoothed, rng.randf_range(-1.0, 1.0), 0.18)
		var body: float = smoothed * exp(-progress * 6.0) * 1.6
		# Thump: a sine that falls in pitch as it fades.
		phase += TAU * pitch_hz * (1.0 - 0.6 * progress) / float(MIX_RATE)
		var thump: float = sin(phase) * exp(-progress * 5.0)
		samples[index] = tanh((crack * 0.9 + body * 0.8 + thump * 0.9) * 1.4)
	return _store(key, samples)


## A short mechanical click, for dry fire, reload steps and switching.
static func click(pitch_hz: float, duration: float = 0.04) -> AudioStreamWAV:
	var key: String = "click:%.1f:%.3f" % [pitch_hz, duration]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var count: int = int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	for index: int in count:
		var t: float = float(index) / float(MIX_RATE)
		var envelope: float = exp(-t / duration * 7.0)
		var tone: float = sin(TAU * pitch_hz * t)
		samples[index] = (tone * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4) * envelope
	return _store(key, samples)


## A dull tick for a bullet hitting a hard surface.
static func impact() -> AudioStreamWAV:
	var key: String = "impact"
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var duration: float = 0.09
	var count: int = int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var smoothed: float = 0.0
	for index: int in count:
		var t: float = float(index) / float(MIX_RATE)
		smoothed = lerpf(smoothed, rng.randf_range(-1.0, 1.0), 0.35)
		samples[index] = (smoothed * 1.3 + sin(TAU * 900.0 * t) * 0.25) * exp(-t / duration * 8.0)
	return _store(key, samples)


## A decaying inharmonic pair of tones for the hinged steel targets.
static func steel_ring() -> AudioStreamWAV:
	const KEY: String = "steel_ring"
	if _cache.has(KEY):
		return _cache[KEY]
	var samples := PackedFloat32Array()
	samples.resize(MIX_RATE)
	for index: int in MIX_RATE:
		var t: float = float(index) / float(MIX_RATE)
		samples[index] = (sin(TAU * 1600.0 * t) + 0.4 * sin(TAU * 2671.0 * t)) * exp(-t * 5.0) * 0.5
	return _store(KEY, samples)


## A short, decaying chirp with an inharmonic overtone. Results are shared
## across HUD instances; all synthesis happens before the first hit.
static func confirmation(start_hz: float, end_hz: float, duration: float) -> AudioStreamWAV:
	var key: String = "confirmation:%.1f:%.1f:%.3f" % [start_hz, end_hz, duration]
	if _cache.has(key):
		return _cache[key]
	var count: int = int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	for index: int in count:
		var t: float = float(index) / float(MIX_RATE)
		var progress: float = t / duration
		phase += TAU * lerpf(start_hz, end_hz, progress) / float(MIX_RATE)
		var envelope: float = minf(t / 0.003, 1.0) * exp(-progress * 4.0)
		samples[index] = (sin(phase) * 0.7 + sin(phase * 1.5) * 0.3) * envelope
	return _store(key, samples)


## A smooth, filtered noise sweep for a blade swing or shield bash.
static func swish(pitch_hz: float, duration: float) -> AudioStreamWAV:
	var key: String = "swish:%.1f:%.3f" % [pitch_hz, duration]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var samples := PackedFloat32Array()
	samples.resize(int(duration * MIX_RATE))
	var filtered: float = 0.0
	for index: int in samples.size():
		var time: float = float(index) / MIX_RATE
		var envelope: float = pow(sin(PI * time / duration), 2.0)
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.1)
		samples[index] = (filtered * 0.7 + sin(TAU * pitch_hz * time) * 0.1) * envelope
	return _store(key, samples)


static func _store(key: String, samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index: int in samples.size():
		data.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	_cache[key] = stream
	return stream
