package main

import "core:math"
import "core:testing"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	@(test)
	weapon_boost_survives_movement_acknowledgements :: proc(t: ^testing.T) {
		for weapon_id in ([]i32{5, 8, 15}) {
			client: Client
			map_inst: shared.Map
			krunker_presentation_fixture(&client, &map_inst)
			defer krunker_presentation_cleanup(&client)
			floor := shared.Object{active = true, collision_type = .BOX, position = {0, -10, 0}, scale = {1000, 10, 1000}}
			append(&map_inst.objects, &floor)
			defer delete(map_inst.objects)
			player := client.me
			shared.player_spawn(player, 4)
			player.loadout[0], player.weapon = weapon_id, client.game.weapons[weapon_id]
			player.ammo[0] = player.weapon.ammo
			player.noclip, player.on_ground, player.swap_timer = false, true, 0
			player.position, player.velocity = {}, {}
			initial := kproto.Krunker_World_Player{
				position = player.position, velocity = player.velocity, on_ground = true,
				can_slide = player.can_slide, weapon_slot = 0,
				has_ack = true, ack_seq = 12, sync_revision = 1,
			}
			frame := shared.Input{delta = f32(KRUNKER_INPUT_SECONDS), move_dir = -1, shoot = true, x_dir = -math.PI/2}
			ammo := player.ammo[0]
			krunker_client_predict_input(&client, &frame)
			if !testing.expect(t, player.velocity.y > 0 && !player.on_ground, "fresh predicted ground shots must immediately lift the shooter") do return
			if !testing.expect(t, len(client.predicted_inputs) == 1 && client.predicted_inputs[0].predicted_weapon_impulse.y > 0,
				"the firing command must retain its boost for movement replay") { return }
			shot_state := initial
			shot_state.position, shot_state.velocity, shot_state.on_ground = player.position, player.velocity, player.on_ground
			shot_state.ack_seq = 13
			frame.shoot = false
			for _ in 0..<4 { krunker_client_predict_input(&client, &frame) }
			predicted_position, predicted_velocity := player.position, player.velocity
			effects := len(client.game.impacts)
			for source in ([]^kproto.Krunker_World_Player{&initial, &initial, &shot_state, &shot_state}) {
				source.sync_revision = client.krunker.local_sync_revision + 1
				krunker_client_apply_motion(&client, player, source, false)
				for axis in 0..<3 {
					testing.expect(t, abs(player.position[axis]-predicted_position[axis]) < 1e-4 &&
						abs(player.velocity[axis]-predicted_velocity[axis]) < 1e-5,
						"acknowledging before/after a boosted shot must preserve the same flight without stacking impulses")
				}
				testing.expect(t, player.ammo[0] == ammo-1 && len(client.game.impacts) == effects && player.shot_seq == 1,
					"boost replay must not repeat ammo consumption, pellets or recoil events")
			}
			shot_state.position, shot_state.velocity = predicted_position, predicted_velocity
			shot_state.ack_seq, shot_state.sync_revision = 17, client.krunker.local_sync_revision+1
			krunker_client_apply_motion(&client, player, &shot_state, false)
			testing.expect(t, len(client.predicted_inputs) == 0 && player.velocity == predicted_velocity,
				"fully confirmed boosts must use authoritative velocity without an extra impulse")
		}
	}

	@(test)
	weapon_boost_metadata_is_not_network_input :: proc(t: ^testing.T) {
		input := shared.Input{seq = 13, move_dir = -1, delta = 0.007, shoot = true, predicted_weapon_impulse = {1, 2, 3}}
		buffer: [128]u8
		size := shared.packet_serialize_input(buffer[:], &input)
		decoded, ok := shared.packet_deserialize_input(buffer[:size])
		testing.expect(t, ok && decoded.shoot && decoded.predicted_weapon_impulse == (shared.Vec3{}),
			"clients must send controls only; the server computes its own boost")
	}
}
