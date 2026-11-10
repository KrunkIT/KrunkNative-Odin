package main

import "core:fmt"
import shared "../shared"

client_audio_present :: proc(client: ^Client, event: shared.Presentation_Event) {
	audio := client.audio
	if audio == nil { return }
	local := client.me != nil && event.uid == client.me.uid
	spatial := !local
	variant := audio.variation % 2
	audio.variation += 1
	switch event.kind {
	case .FIRE:
		if event.weapon_id < 0 || int(event.weapon_id) >= len(client.game.weapons) { return }
		weapon := client.game.weapons[event.weapon_id]
		if weapon == nil { return }
		path := audio_weapon_path(weapon)
		if weapon.melee && len(weapon.sound) == 0 { path = fmt.tprintf("%ssound/swsh_def_%d.mp3", shared.assets_path(), variant) }
		audio_play(audio, path, .EFFECTS, 0.8, event.position, spatial, 600, 3)
	case .STEP:
		audio_play_effect(audio, fmt.tprintf("step_%d", variant), .FOOTSTEPS, 0.65 * (1 - event.value * 0.75), event.position, spatial, 90, 1)
	case .JUMP: audio_play_effect(audio, "jump_0", .FOOTSTEPS, 0.45, event.position, spatial, 90, 1)
	case .LAND: audio_play_effect(audio, "land_1", .FOOTSTEPS, 0.65, event.position, spatial, 100, 1)
	case .SLIDE: audio_play_effect(audio, "slide_0", .FOOTSTEPS, 0.5, event.position, spatial, 100, 1)
	case .RELOAD:
		if local { audio_play_effect(audio, "reload_1", .EFFECTS, 0.7) }
	case .SWAP:
		if local { audio_play_effect(audio, "select_0", .EFFECTS, 0.45) }
	case .DAMAGE:
		if local { audio_play_effect(audio, fmt.tprintf("takedmg_%d", variant), .EFFECTS, 0.65, priority = 4) }
	case .HIT:
		if local { audio_play_effect(audio, event.headshot ? "crit_0" : "hit_0", .EFFECTS, 0.7, priority = 4) }
	case .EXPLOSION: audio_play_effect(audio, "explosion", .EFFECTS, 0.85, event.position, true, 700, 3)
	}
}

client_audio_tick :: proc(client: ^Client, delta: f32) {
	audio_update_listener(client.audio, &client.camera)
	for event in client.game.presentation_events { client_audio_present(client, event) }
	clear(&client.game.presentation_events)
	if client.audio != nil && client.krunker.connected {
		world := &client.krunker_world
		if world.hit_revision != client.audio.hit_revision {
			client.audio.hit_revision = world.hit_revision
			if world.hit_revision > 0 { audio_play_effect(client.audio, world.hit_lethal ? "headshot_0" : "hit_0", gain = 0.7, priority = 4) }
		}
	}
	if client.audio_settings_dirty {
		client.audio_save_delay -= delta
		if client.audio_save_delay <= 0 {
			client.audio_settings_dirty = false
			audio_settings_save(client.audio_settings)
		}
	}
}
