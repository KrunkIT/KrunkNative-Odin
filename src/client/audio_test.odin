package main

import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import ma "vendor:miniaudio"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	audio_test_energy :: proc(t: ^testing.T, audio: ^Audio_System) -> (left, right: f64) {
		buffer := make([]f32, 48000)
		defer delete(buffer)
		testing.expect(t, ma.engine_read_pcm_frames(&audio.engine, raw_data(buffer), 24000, nil) == .SUCCESS, "offline mixer must render PCM")
		for i := 0; i < len(buffer); i += 2 {
			left += f64(buffer[i]) * f64(buffer[i])
			right += f64(buffer[i+1]) * f64(buffer[i+1])
		}
		return
	}

	@(test)
	audio_decodes_assets_and_mixes_stereo :: proc(t: ^testing.T) {
		config := shared.config_load_gameplay()
		defer shared.config_destroy_gameplay(config)
		audio := audio_create(config.weapons, {1, 1, 1, 1}, true)
		if !testing.expect(t, audio != nil, "offline audio engine must initialize without a physical output") { return }
		defer audio_destroy(audio)
		for path, sample in audio.samples {
			testing.expect(t, sample.ready, path)
		}
		for weapon in config.weapons {
			if weapon == nil { continue }
			path := audio_weapon_path(weapon)
			sample, found := audio.samples[path]
			testing.expect(t, found && sample.ready, "every configured weapon must have a decoded sound")
		}
		camera := camera_init(1)
		audio_update_listener(audio, &camera)
		testing.expect(t, audio_play_effect(audio, "weapon_4", position = {30, 0, -10}, spatial = true), "gunshot must start")
		left, right := audio_test_energy(t, audio)
		testing.expect(t, right > 0.01 && right > left * 1.1, "sound to the right must favor the right speaker")
		audio_stop_all(audio)
		audio_test_energy(t, audio)
		camera.rotation.y = math.PI
		audio_update_listener(audio, &camera)
		testing.expect(t, audio_play_effect(audio, "weapon_4", position = {30, 0, -10}, spatial = true))
		turned_left, turned_right := audio_test_energy(t, audio)
		testing.expect(t, turned_left > 0.01 && turned_left > turned_right * 1.1, "turning around must reverse stereo direction")
		audio_set_settings(audio, {0, 1, 1, 1})
		muted_left, muted_right := audio_test_energy(t, audio)
		testing.expect(t, muted_left + muted_right < 0.000001, "master mute must silence active voices immediately")
		testing.expect(t, !audio_play_effect(audio, "weapon_4"), "muted effects must not consume new voices")
		audio_set_settings(audio, {1, 1, 0, 1})
		testing.expect(t, !audio_play_effect(audio, "step_0", .FOOTSTEPS), "footstep mute must be independent")
		testing.expect(t, audio_play_effect(audio, "hit_0"), "footstep mute must preserve other effects")
		audio_stop_all(audio)
		audio_test_energy(t, audio)
		for _ in 0 ..< MAX_AUDIO_VOICES {
			testing.expect(t, audio_play_effect(audio, "weapon_1", priority = 4), "voice pool must support overlapping effects")
		}
		testing.expect(t, !audio_play_effect(audio, "step_0", priority = 1), "footsteps cannot steal more important voices")
		testing.expect(t, audio_play_effect(audio, "hit_0", priority = 4), "important feedback may replace the oldest equal-priority voice")
		missing_path := "assets/sound/__missing_audio_test.mp3"
		missing := audio_load_sample(audio, missing_path)
		cache_count := len(audio.samples)
		testing.expect(t, !missing.ready && audio_load_sample(audio, missing_path) == missing && len(audio.samples) == cache_count,
			"missing assets must fail once and remain cached without repeated loads")
		testing.expect(t, !audio_play_effect(audio, "weapon_4", position = {9999, 0, 0}, spatial = true), "inaudible distant effects must not take voices")
		client := Client{audio = audio, krunker = {connected = true}, krunker_world = {hit_revision = 1}}
		before := audio.serial
		client_audio_tick(&client, 0)
		client_audio_tick(&client, 0)
		testing.expect(t, audio.serial == before + 1, "confirmed live hits must sound once per server revision")
		client.krunker_world.hit_revision = 0
		client_audio_tick(&client, 0)
		testing.expect(t, audio.serial == before + 1, "resetting a lobby cannot play a stale hit sound")
	}

	@(test)
	audio_fresh_actions_and_server_echoes :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		client.game.presentation_enabled = true
		frame := shared.Input{delta = 0.007, move_dir = -1, shoot = true}
		krunker_client_predict_input(&client, &frame, 1)
		if !testing.expect(t, len(client.game.presentation_events) == 1 && client.game.presentation_events[0].kind == .FIRE,
			"fresh prediction must emit one gunshot") { return }
		source := kproto.Krunker_World_Player{position = client.me.position, weapon_slot = 0, has_ack = true, ack_seq = 12, sync_revision = 1}
		for _ in 0 ..< 3 {
			krunker_client_apply_motion(&client, client.me, &source, false)
			source.sync_revision += 1
		}
		testing.expect(t, len(client.game.presentation_events) == 1, "reconciliation must not replay sound")
		append(&client.krunker_world.shots, kproto.Krunker_World_Shot{sid = client.krunker_world.local_sid})
		krunker_client_present_shots(&client)
		testing.expect(t, len(client.game.presentation_events) == 1, "a server echo cannot duplicate the predicted gunshot")
		clear(&client.game.presentation_events)
		frame.shoot, frame.reload = false, true
		krunker_client_predict_input(&client, &frame, 1.01)
		testing.expect(t, len(client.game.presentation_events) == 1 && client.game.presentation_events[0].kind == .RELOAD,
			"starting a reload must emit a single effect")
		krunker_client_predict_input(&client, &frame, 1.02)
		testing.expect(t, len(client.game.presentation_events) == 1, "holding reload cannot repeat its sound")
		clear(&client.game.presentation_events)
		for _ in 0 ..< 400 { shared.player_emit_presentation(client.me, .STEP) }
		testing.expect(t, len(client.game.presentation_events) == 256, "event bursts must stay bounded")
		client.game.presentation_enabled = false
		clear(&client.game.presentation_events)
		shared.player_emit_presentation(client.me, .STEP)
		testing.expect(t, len(client.game.presentation_events) == 0, "dedicated servers must not collect audio events")
	}

	@(test)
	audio_settings_roundtrip :: proc(t: ^testing.T) {
		path := "bin/audio-settings-test.json"
		defer os.remove(path)
		settings := Audio_Settings{master = 0, effects = 0.7, footsteps = 0.3, ui = 1}
		testing.expect(t, audio_settings_save(settings, path) && audio_settings_load(path) == settings, "volume settings must survive restarting")
		testing.expect(t, os.write_entire_file(path, string(`{"master":5,"effects":-1,"footsteps":0.4,"ui":0}`)) == nil)
		loaded := audio_settings_load(path)
		testing.expect(t, loaded == Audio_Settings{1, 0, 0.4, 0}, "settings must clamp out-of-range values")
		testing.expect(t, os.write_entire_file(path, string("invalid json")) == nil)
		testing.expect(t, audio_settings_load(path) == DEFAULT_AUDIO_SETTINGS, "invalid settings must fall back safely")
		custom := shared.Weapon{sound = "mods/custom/fire.wav"}
		testing.expect(t, strings.has_suffix(audio_weapon_path(&custom), "mods/custom/fire.wav"), "custom weapon audio paths must be preserved")
	}

	// Explicit hardware smoke check; normal tests remain device independent.
	when #config(AUDIO_DEVICE_SMOKE, false) {
		@(test)
		audio_output_device_smoke :: proc(t: ^testing.T) {
			audio := audio_create(nil, DEFAULT_AUDIO_SETTINGS)
			if !testing.expect(t, audio != nil, "system playback device must initialize") { return }
			audio_destroy(audio)
		}
	}
}
