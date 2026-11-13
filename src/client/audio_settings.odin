package main

import "core:encoding/json"
import "core:fmt"
import "core:os"

Audio_Settings :: struct { master, effects, footsteps, ui: f32 }
DEFAULT_AUDIO_SETTINGS :: Audio_Settings{master = 0.8, effects = 1, footsteps = 0.8, ui = 0.6}
AUDIO_SETTINGS_PATH :: "audio-settings.json"

audio_settings_clamp :: proc(settings: Audio_Settings) -> Audio_Settings {
	return {clamp(settings.master, 0, 1), clamp(settings.effects, 0, 1), clamp(settings.footsteps, 0, 1), clamp(settings.ui, 0, 1)}
}

audio_settings_load :: proc(path: string = AUDIO_SETTINGS_PATH) -> Audio_Settings {
	settings := DEFAULT_AUDIO_SETTINGS
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil { return settings }
	defer delete(data)
	if json.unmarshal(data, &settings) != nil {
		fmt.eprintln("[Audio] Invalid audio settings; using defaults.")
		return DEFAULT_AUDIO_SETTINGS
	}
	return audio_settings_clamp(settings)
}

audio_settings_save :: proc(settings: Audio_Settings, path: string = AUDIO_SETTINGS_PATH) -> bool {
	data, err := json.marshal(audio_settings_clamp(settings))
	if err != nil { return false }
	defer delete(data)
	if os.write_entire_file(path, data) != nil {
		fmt.eprintln("[Audio] Could not save volume settings.")
		return false
	}
	return true
}
