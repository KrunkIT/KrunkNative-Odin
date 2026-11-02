package main

import "core:math"
import "core:testing"
import shared "../shared"

when ODIN_TEST {
	@(test)
	spread_reconciliation_restores_accuracy :: proc(t: ^testing.T) {
		config := shared.config_load_gameplay()
		defer shared.config_destroy_gameplay(config)
		map_inst := shared.Map{death_y = -1000, config = {speed = {1, 1, 1}, air_accel = 1}}
		client: Client
		shared.game_configure(&client.game, &config.game, []^shared.Map{&map_inst}, nil, config.weapons, config.classes)
		shared.game_init(&client.game, 0, 0, false)
		defer shared.game_destroy(&client.game)
		defer delete(client.predicted_inputs)
		player := shared.player_init(&client.game)
		shared.game_players_add(&client.game, player)
		shared.player_spawn(player, 0)
		player.noclip = true
		player.spread_plus = 999
		state := shared.Packet_Player_State{
			active = true, is_you = true, on_ground = true, can_slide = true,
			position = {10, 20, 30}, velocity = {0.02, 0, 0}, spread_plus = 80, ack_seq = 1,
		}
		append(&client.predicted_inputs,
			shared.Input{seq = 1, delta = 0.01, move_dir = 0, shoot = true},
			shared.Input{seq = 2, delta = 0.01, move_dir = 0, shoot = true})
		client_reconcile_local_player(&client, player, &state, true)
		first_position := player.position
		first_spread_plus := player.spread_plus
		first_spread := player.spread
		testing.expect(t, len(client.predicted_inputs) == 1, "acknowledged movement must not be replayed")
		testing.expect(t, first_spread_plus > 0 && first_spread_plus < 100, "restore authoritative accuracy before applying pending movement")
		player.position = {50, 50, 50}
		player.spread_plus = 1234
		client_reconcile_local_player(&client, player, &state, true)
		testing.expect(t, player.position == first_position && abs(player.spread_plus - first_spread_plus) < 1e-5 && abs(player.spread - first_spread) < 1e-5,
			"repeated snapshots must produce identical accuracy rather than accumulating replay spread")
		testing.expect(t, player.shot_seq == 0 && len(client.game.impacts) == 0 && len(client.game.projectiles) == 0,
			"accuracy reconciliation must not duplicate any shot effects")
		testing.expect(t, !math.is_nan(player.spread), "reconciled spread must remain finite")
	}
}
