package main

import "core:testing"
import shared "../shared"
import kproto "../krunker"
import menuui "../menu"

when ODIN_TEST {
	@(test)
	auto_pistol_and_techy_9_have_distinct_fire_modes :: proc(t: ^testing.T) {
		// Check held-trigger behavior in local simulation and live prediction.
		for predicted in ([]bool{false, true}) {
			for id in ([]i32{16, 21}) {
				client: Client
				map_inst: shared.Map
				krunker_presentation_fixture(&client, &map_inst)
				defer krunker_presentation_cleanup(&client)
				player := client.me
				shared.player_spawn(player, 0, id)
				shared.player_swap_weapon(player, 1, true, true, true)
				player.swap_timer = 0
				frame := shared.Input{delta = 0.007, move_dir = -1, shoot = true}
				// At 7 ms simulation ticks the Auto Pistol fires every 105 ms;
				// Techy-9 finishes one burst, then requires a trigger release.
				for _ in 0..<61 { shared.player_proc_input(player, &frame, predicted, false, predicted, predicted) }
				shots: u32 = id == 16 ? 5 : 3
				testing.expect(t, player.shot_seq == shots && player.ammo[1] == 15-shots,
					"holding fire must repeat Auto Pistol shots but produce only one three-round Techy-9 burst")
				frame.shoot = false
				for _ in 0..<60 { shared.player_proc_input(player, &frame, predicted, false, predicted, predicted) }
				testing.expect(t, player.shot_seq == shots, "releasing fire must stop both secondaries")
				frame.shoot = true
				shared.player_proc_input(player, &frame, predicted, false, predicted, predicted)
				frame.shoot = false
				for _ in 0..<28 { shared.player_proc_input(player, &frame, predicted, false, predicted, predicted) }
				shots += id == 16 ? 1 : 3
				testing.expect(t, player.shot_seq == shots && player.ammo[1] == 15-shots,
					"a new press must restart fire, and Techy-9 must finish its burst after release")
				frame.reload = true
				shared.player_proc_input(player, &frame, predicted, false, predicted, predicted)
				frame.reload = false
				for _ in 0..<150 { shared.player_proc_input(player, &frame, predicted, false, predicted, predicted) }
				testing.expect(t, player.reload_timer == 0 && player.ammo[1] == 15,
					"both secondary magazines must refill after their one-second reload")
			}
		}
	}

	@(test)
	secondary_preferences_apply_on_spawn :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		client.local_practice, client.selected_class = true, 0
		shared.player_spawn(client.me, 0)
		for id in ([]i32{2, 10, 11, 15, 16, 21}) {
			old_loadout := client.me.loadout[1]
			client.menu.page = .LOADOUT
			menu_apply_action(&client, {kind = .SELECT_SECONDARY, index = id})
			testing.expect(t, client.selected_secondary == id && client.menu.page == .LOADOUT && client.me.loadout[1] == old_loadout,
				"choosing a secondary must preserve the current life")
			shared.player_spawn(client.me, 0)
			testing.expect(t, client.me.loadout[1] == id && client.me.ammo[1] == client.game.weapons[id].ammo,
				"the next spawn must use the selected secondary with its own magazine")
		}
		shared.player_spawn(client.me, 0, 1)
		testing.expect(t, client.me.loadout[1] == 2, "primary weapons must never be accepted as sidearms")
		client.game.config.no_secondaries = true
		shared.player_spawn(client.me, 0, 15)
		testing.expect(t, client.me.loadout_size == 2 && client.me.loadout[1] == 12, "lobby restrictions must remove the extra sidearm")
		client.game.config.no_secondaries = false
		shared.player_spawn(client.me, 2, 15)
		testing.expect(t, client.me.loadout_size == 2 && client.me.loadout[1] == 12, "Run N Gun must keep its class loadout without an extra secondary")
	}

	@(test)
	secondary_requests_keep_failed_selection_open :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		defer delete(client.selection_status)
		client.krunker.connected, client.selected_class, client.selected_secondary = true, 0, 2
		client.krunker.class_index, client.krunker.secondary_index = 0, 2
		client.menu.page = .LOADOUT
		menu_apply_action(&client, {kind = .SELECT_SECONDARY, index = 15}, class_selection_test_send)
		testing.expect(t, client.menu.page == .LOADOUT && client.selected_secondary == 2 && client.krunker.secondary_index == 2 && len(client.selection_status) > 0,
			"failed sends must retain the previous choice and leave the picker open")
		client.krunker.q_index = 1
		menu_apply_action(&client, {kind = .SELECT_SECONDARY, index = 15}, class_selection_test_send)
		testing.expect(t, client.menu.page == .LOADOUT && client.selected_secondary == 15 && client.krunker.secondary_index == 15 && len(client.selection_status) == 0,
			"a successful request must carry the secondary and keep the class loadout open")
		client.game.config.no_secondaries = true
		menu_apply_action(&client, {kind = .SELECT_SECONDARY, index = 10}, class_selection_test_send)
		testing.expect(t, client.selected_secondary == 15 && len(client.selection_status) > 0, "disabled secondaries must explain why and preserve the preference")
	}

	@(test)
	secondary_live_wire_and_roster :: proc(t: ^testing.T) {
		for id in ([]i32{2, 10, 11, 15, 16, 21, -1}) {
			counter: u8
			encoded := krunker_ws_message("class", &counter, 0, 0, 0, id)
			messages, _, error_text := kproto.krunker_msgpack_decode_packet(encoded[:])
			testing.expect(t, len(error_text) == 0 && len(messages) == 1)
			packet := messages[0].([]kproto.Krunker_Msgpack_Value)
			entries := packet[2].([]kproto.Krunker_Msgpack_Map_Entry)
			if id < 0 {
				_, absent := entries[1].value.(kproto.Krunker_Msgpack_Nil)
				testing.expect(t, absent, "classes without sidearms must send nil")
			} else {
				testing.expect(t, kproto.krunker_world_i32(entries[1].value) == id, "class requests must include the selected secondary")
			}
			delete(encoded)
			encoded = krunker_ws_message("en", &counter, 0, 0, 0, id)
			messages, _, error_text = kproto.krunker_msgpack_decode_packet(encoded[:])
			packet = messages[0].([]kproto.Krunker_Msgpack_Value)
			loadout := packet[1].([]kproto.Krunker_Msgpack_Value)
			testing.expect(t, kproto.krunker_world_i32(loadout[5]) == (id < 0 ? 2 : id), "entry must carry the same sidearm as class selection")
			delete(encoded)
		}
		world := kproto.Krunker_World_State{local_sid = 7}
		defer kproto.krunker_world_reset(&world)
		roster: [53]kproto.Krunker_Msgpack_Value
		roster[0], roster[1], roster[6], roster[15] = "socket", i64(7), i64(0), i64(2)
		packet := []kproto.Krunker_Msgpack_Value{"0", roster[:]}
		testing.expect(t, kproto.krunker_world_apply_packet(&world, packet) && world.players[0].secondary_id == 2,
			"the server's accepted pistol must win over an unaccepted Sawed Off request")
		roster[15] = i64(15)
		testing.expect(t, kproto.krunker_world_apply_packet(&world, packet) && world.players[0].secondary_id == 15,
			"accepted secondary changes must be retained from the authoritative roster")
	}
}
