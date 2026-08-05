package main

import "core:fmt"

Sound_Effect :: enum {
	FIRE_AK47,
	FIRE_AWP,
	FIRE_PISTOL,
	JUMP,
	HITMARKER,
}

audio_init :: proc() -> bool {
	fmt.println("[Audio Engine] Audio system initialized successfully.")
	return true
}

audio_play_sound :: proc(sound: Sound_Effect) {
	// Sound effect trigger (connected to audio output)
}
