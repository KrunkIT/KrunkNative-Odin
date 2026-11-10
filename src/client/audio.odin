package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import ma "vendor:miniaudio"
import shared "../shared"

Audio_Channel :: enum { EFFECTS, FOOTSTEPS, UI }
MAX_AUDIO_VOICES :: 64

Audio_Sample :: struct { sound: ma.sound, ready: bool }
Audio_Voice :: struct {
	sound: ma.sound,
	sample: ^Audio_Sample,
	channel: Audio_Channel,
	gain: f32,
	priority: int,
	serial: u64,
}
Audio_System :: struct {
	engine: ma.engine,
	samples: map[string]^Audio_Sample,
	voices: [MAX_AUDIO_VOICES]Audio_Voice,
	settings: Audio_Settings,
	listener_position: shared.Vec3,
	serial, hit_revision: u64,
	variation: u32,
}

audio_weapon_path :: proc(weapon: ^shared.Weapon) -> string {
	if weapon == nil { return "" }
	name := len(weapon.sound) > 0 ? weapon.sound : weapon.src
	if weapon.melee && len(weapon.sound) == 0 { name = "swsh_def_0" }
	if name == "weapon-7" { name = "weapon_7" }
	if len(name) == 0 { return "" }
	if strings.contains(name, ".") { return fmt.tprintf("%s%s", shared.assets_path(), name) }
	return fmt.tprintf("%ssound/%s.mp3", shared.assets_path(), name)
}

audio_load_sample :: proc(audio: ^Audio_System, path: string) -> ^Audio_Sample {
	if len(path) == 0 { return nil }
	if sample, found := audio.samples[path]; found { return sample }
	sample := new(Audio_Sample)
	audio.samples[strings.clone(path)] = sample
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	result := ma.sound_init_from_file(&audio.engine, cpath, {.DECODE}, nil, nil, &sample.sound)
	sample.ready = result == .SUCCESS
	if !sample.ready { fmt.eprintf("[Audio] Cannot load %s (%v); this effect will be silent.\n", path, result) }
	return sample
}

audio_create :: proc(weapons: []^shared.Weapon, settings: Audio_Settings, no_device: bool = false) -> ^Audio_System {
	audio := new(Audio_System)
	config := ma.engine_config_init()
	config.channels, config.sampleRate = 2, 48000
	config.noDevice = b32(no_device)
	result := ma.engine_init(&config, &audio.engine)
	if result != .SUCCESS {
		fmt.eprintf("[Audio] Output unavailable (%v); continuing without sound.\n", result)
		free(audio)
		return nil
	}
	audio.samples = make(map[string]^Audio_Sample)
	// Short effects decode before gameplay, never on the first trigger pull.
	manifest_path := shared.concat(shared.assets_path(), "config/sound-assets.txt")
	defer delete(manifest_path)
	manifest, err := os.read_entire_file_from_path(manifest_path, context.allocator)
	if err == nil {
		contents := string(manifest)
		for raw_line in strings.split_lines_iterator(&contents) {
			line := strings.trim_space(raw_line)
			if len(line) == 0 || strings.has_prefix(line, "#") { continue }
			audio_load_sample(audio, fmt.tprintf("%s%s", shared.assets_path(), line))
		}
		delete(manifest)
	} else { fmt.eprintln("[Audio] Sound manifest missing; effects will load on demand.") }
	for weapon in weapons { if weapon != nil { audio_load_sample(audio, audio_weapon_path(weapon)) } }
	audio_set_settings(audio, settings)
	fmt.printf("[Audio] Stereo mixer ready: %d cached effects, %d voices.\n", len(audio.samples), MAX_AUDIO_VOICES)
	return audio
}

audio_stop_all :: proc(audio: ^Audio_System) {
	if audio == nil { return }
	for &voice in audio.voices { if voice.sample != nil { ma.sound_stop(&voice.sound) } }
}

audio_destroy :: proc(audio: ^Audio_System) {
	if audio == nil { return }
	for &voice in audio.voices { if voice.sample != nil { ma.sound_uninit(&voice.sound) } }
	for path, sample in audio.samples {
		if sample.ready { ma.sound_uninit(&sample.sound) }
		free(sample)
		delete(path)
	}
	delete(audio.samples)
	ma.engine_uninit(&audio.engine)
	free(audio)
}

audio_channel_gain :: proc(settings: Audio_Settings, channel: Audio_Channel) -> f32 {
	switch channel {
	case .EFFECTS: return settings.effects
	case .FOOTSTEPS: return settings.footsteps
	case .UI: return settings.ui
	}
	return 0
}

audio_set_settings :: proc(audio: ^Audio_System, settings: Audio_Settings) {
	if audio == nil { return }
	audio.settings = settings
	ma.engine_set_volume(&audio.engine, settings.master)
	for &voice in audio.voices {
		if voice.sample != nil { ma.sound_set_volume(&voice.sound, voice.gain * audio_channel_gain(settings, voice.channel)) }
	}
}

audio_update_listener :: proc(audio: ^Audio_System, camera: ^Camera) {
	if audio == nil { return }
	audio.listener_position = camera.position
	ma.engine_listener_set_position(&audio.engine, 0, camera.position.x, camera.position.y, camera.position.z)
	pitch, yaw := camera.rotation.x, camera.rotation.y
	ma.engine_listener_set_direction(&audio.engine, 0, -math.sin(yaw)*math.cos(pitch), math.sin(pitch), -math.cos(yaw)*math.cos(pitch))
	ma.engine_listener_set_world_up(&audio.engine, 0, 0, 1, 0)
}

// The mixer runs in miniaudio's C thread; it never calls back into Odin or
// touches gameplay memory. Voices share decoded samples and have bounded cost.
audio_play :: proc(audio: ^Audio_System, path: string, channel: Audio_Channel = .EFFECTS,
	gain: f32 = 1, position: shared.Vec3 = {}, spatial: bool = false, radius: f32 = 400, priority: int = 2) -> bool {
	if audio == nil || audio.settings.master <= 0 || audio_channel_gain(audio.settings, channel) <= 0 { return false }
	if spatial {
		delta := position - audio.listener_position
		if delta.x*delta.x + delta.y*delta.y + delta.z*delta.z >= radius*radius { return false }
	}
	sample := audio_load_sample(audio, path)
	if sample == nil || !sample.ready { return false }
	chosen := -1
	for &voice, i in audio.voices {
		if voice.sample == nil || !bool(ma.sound_is_playing(&voice.sound)) { chosen = i; break }
		if chosen < 0 || voice.priority < audio.voices[chosen].priority ||
			voice.priority == audio.voices[chosen].priority && voice.serial < audio.voices[chosen].serial { chosen = i }
	}
	voice := &audio.voices[chosen]
	if voice.sample != nil && bool(ma.sound_is_playing(&voice.sound)) && voice.priority > priority { return false }
	if voice.sample != sample {
		if voice.sample != nil { ma.sound_uninit(&voice.sound); voice.sample = nil }
		if ma.sound_init_copy(&audio.engine, &sample.sound, {}, nil, &voice.sound) != .SUCCESS { return false }
		voice.sample = sample
	} else { ma.sound_stop(&voice.sound) }
	ma.sound_seek_to_pcm_frame(&voice.sound, 0)
	voice.channel, voice.gain, voice.priority = channel, gain, priority
	audio.serial += 1
	voice.serial = audio.serial
	ma.sound_set_volume(&voice.sound, gain * audio_channel_gain(audio.settings, channel))
	ma.sound_set_spatialization_enabled(&voice.sound, b32(spatial))
	ma.sound_set_position(&voice.sound, position.x, position.y, position.z)
	ma.sound_set_attenuation_model(&voice.sound, .linear)
	ma.sound_set_min_distance(&voice.sound, min(10, radius * 0.1))
	ma.sound_set_max_distance(&voice.sound, radius)
	ma.sound_set_rolloff(&voice.sound, 1)
	ma.sound_set_doppler_factor(&voice.sound, 0)
	return ma.sound_start(&voice.sound) == .SUCCESS
}

audio_play_effect :: proc(audio: ^Audio_System, name: string, channel: Audio_Channel = .EFFECTS,
	gain: f32 = 1, position: shared.Vec3 = {}, spatial: bool = false, radius: f32 = 400, priority: int = 2) -> bool {
	return audio_play(audio, fmt.tprintf("%ssound/%s.mp3", shared.assets_path(), name), channel, gain, position, spatial, radius, priority)
}
