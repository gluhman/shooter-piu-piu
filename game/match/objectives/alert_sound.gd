extends RefCounted
## Short, non-positional cues so both teams can hear public objective events.

const SAMPLE_RATE := 24000
const CUES := {
	"plant": [360.0, 305.0, 710.0],
	"capture": [523.25, 659.25, 783.99],
	"defuse": [659.25, 523.25],
}
static var _streams: Dictionary[String, AudioStreamWAV] = {}


static func stream(cue: String) -> AudioStreamWAV:
	if _streams.has(cue):
		return _streams[cue]
	if not CUES.has(cue):
		return null
	const NOTE_SECONDS := 0.09
	const NOTE_SAMPLES := int(NOTE_SECONDS * SAMPLE_RATE)
	var notes: Array = CUES[cue]
	var bytes := PackedByteArray()
	bytes.resize(notes.size() * NOTE_SAMPLES * 2)
	for note in notes.size():
		var pitch: float = notes[note]
		for index in NOTE_SAMPLES:
			var time := float(index) / SAMPLE_RATE
			var phase := TAU * pitch * time
			var envelope := smoothstep(0.0, 0.008, time) * (1.0 - smoothstep(0.040, NOTE_SECONDS, time))
			var sample_value := (sin(phase) + 0.20 * sin(phase * 2.0)) * envelope * 0.36
			bytes.encode_s16((note * NOTE_SAMPLES + index) * 2, roundi(sample_value * 32767.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = SAMPLE_RATE
	sound.data = bytes
	_streams[cue] = sound
	return sound
