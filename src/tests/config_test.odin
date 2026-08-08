package main

import "core:fmt"
import "core:encoding/endian"
import "core:math"

import shared "../shared"

test_net_send_queue :: proc() -> bool {
	queue := shared.Net_Send_Queue{}
	prefix := []byte{1, 2, 3, 4}
	if !shared.net_send_queue_push(&queue, prefix) {
		fmt.eprintln("Network send queue initial append test failed")
		return false
	}

	shared.net_send_queue_consume(&queue, 3)
	large := make([]byte, shared.NET_SEND_QUEUE_CAPACITY - 4)
	defer delete(large)
	for &value in large {
		value = 0x5a
	}
	if !shared.net_send_queue_push(&queue, large) {
		fmt.eprintln("Network send queue large append test failed")
		return false
	}

	// Leave one byte at the physical end, then append again. This exercises the
	// compaction path used after a real socket accepts only part of a frame.
	shared.net_send_queue_consume(&queue, len(large))
	tail := []byte{5, 6, 7, 8}
	if !shared.net_send_queue_push(&queue, tail) {
		fmt.eprintln("Network send queue compaction test failed")
		return false
	}

	pending := shared.net_send_queue_pending(&queue)
	contents_ok := len(pending) == 5 && pending[0] == 0x5a
	for value, index in tail {
		contents_ok = contents_ok && pending[index + 1] == value
	}
	if !contents_ok {
		fmt.eprintln("Network send queue ordering test failed")
		return false
	}

	too_large := make([]byte, shared.NET_SEND_QUEUE_CAPACITY)
	defer delete(too_large)
	if shared.net_send_queue_push(&queue, too_large) {
		fmt.eprintln("Network send queue overflow test failed")
		return false
	}

	shared.net_send_queue_consume(&queue, len(pending))
	if len(shared.net_send_queue_pending(&queue)) != 0 {
		fmt.eprintln("Network send queue drain test failed")
		return false
	}

	fmt.println("Network send queue tests OK")
	return true
}

test_snapshot_interpolation :: proc() -> bool {
	config := shared.DEFAULT_GAME_CONFIG
	game := shared.Game{config = config}
	player := shared.Player{
		game = &game,
		interpolate = true,
		send_rate = 10,
		interp_pos_start = {0, 0, 0},
		interp_pos_end = {10, 5, -2},
		interp_dir_start = {0.25, math.PI - 0.1},
		interp_dir_end = {-0.25, -math.PI + 0.1},
	}

	// Two snapshot intervals must stop at the target instead of extrapolating
	// past it. Yaw interpolation must also take the short path across +/- PI.
	shared.player_interpolate(&player, 0.2)
	position_ok := player.position == player.interp_pos_end
	pitch_ok := abs(player.direction.x - player.interp_dir_end.x) < 0.0001
	yaw_ok := abs(shared.normalize_angle(player.direction.y - player.interp_dir_end.y)) < 0.0001
	if !position_ok || !pitch_ok || !yaw_ok {
		fmt.eprintln("Snapshot interpolation clamp/angle test failed")
		return false
	}

	fmt.println("Snapshot interpolation tests OK")
	return true
}

test_gameplay_config :: proc() -> bool {
	config := shared.config_load_gameplay()
	defer shared.config_destroy_gameplay(config)

	defaults_ok :=
		len(config.weapons) == len(shared.WEAPONS_LIST) &&
		len(config.classes) == len(shared.CLASSES_LIST) &&
		config.weapons[0] != shared.WEAPONS_LIST[0] &&
		config.weapons[0].name == shared.WEAPONS_LIST[0].name &&
		config.weapons[0].damage == shared.WEAPONS_LIST[0].damage &&
		config.classes[0].name == shared.CLASSES_LIST[0].name &&
		config.classes[0].health == shared.CLASSES_LIST[0].health
	if !defaults_ok {
		fmt.eprintln("Gameplay config default-copy test failed")
		return false
	}

	spray_index := shared.class_config_index("spray_n_pray")
	lmg_index := shared.weapon_config_index("lmg")
	spray_loadout_ok :=
		spray_index >= 0 && lmg_index >= 0 &&
		len(shared.CLASSES_LIST[spray_index].loadout) > 0 &&
		shared.CLASSES_LIST[spray_index].loadout[0] == i32(lmg_index) &&
		len(config.classes[spray_index].loadout) > 0 &&
		config.classes[spray_index].loadout[0] == i32(lmg_index)
	if !spray_loadout_ok {
		fmt.eprintln("Spray N Pray LMG loadout test failed")
		return false
	}

	weapon_default_damage := shared.WEAPONS_LIST[0].damage
	class_default_name := shared.CLASSES_LIST[0].name

	weapon_ok := shared.config_apply_toml(
		config,
		`
[weapons.awp]
damage = 42.5
origin = [1, 2, 3]
sound = "sounds/awp_fire.wav"
`,
	)
	class_ok := shared.config_apply_toml(
		config,
		`
[classes.triggerman]
name = "Configured"
health = 125
`,
	)
	override_ok :=
		weapon_ok &&
		class_ok &&
		config.weapons[0].damage == 42.5 &&
		config.weapons[0].origin == shared.Vec3{1, 2, 3} &&
		config.weapons[0].sound == "sounds/awp_fire.wav" &&
		config.classes[0].name == "Configured" &&
		config.classes[0].health == 125 &&
		shared.WEAPONS_LIST[0].damage == weapon_default_damage &&
		shared.CLASSES_LIST[0].name == class_default_name
	if !override_ok {
		fmt.eprintln("Gameplay config partial-override test failed")
		return false
	}

	// Named loadouts must resolve to stable weapon indices.
	loadout_ok := shared.config_apply_toml(
		config,
		`
[classes.trooper]
loadout = ["ak47", "deagle", "knife"]
`,
	)
	if !loadout_ok ||
		len(config.classes[13].loadout) != 3 ||
		config.classes[13].loadout[0] != 1 ||
		config.classes[13].loadout[1] != 10 ||
		config.classes[13].loadout[2] != 12 {
		fmt.eprintln("Gameplay config named-loadout resolution test failed")
		return false
	}

	fmt.println("Gameplay config tests OK")
	return true
}

test_objective_combat_state :: proc() -> bool {
	rotation_maps_ok := len(shared.ROTATION_MAPS) == 4 && shared.ROTATION_MAPS[0] == 2 && shared.ROTATION_MAPS[1] == 4 && shared.ROTATION_MAPS[2] == 12 && shared.ROTATION_MAPS[3] == 14
	rotation_classes_ok := len(shared.ROTATION_CLASSES) == 9 && shared.ROTATION_CLASSES[0] == 0 && shared.ROTATION_CLASSES[1] == 1 && shared.ROTATION_CLASSES[2] == 2 && shared.ROTATION_CLASSES[3] == 3 && shared.ROTATION_CLASSES[4] == 5 && shared.ROTATION_CLASSES[5] == 6 && shared.ROTATION_CLASSES[6] == 8 && shared.ROTATION_CLASSES[7] == 12 && shared.ROTATION_CLASSES[8] == 13
	if !rotation_maps_ok || !rotation_classes_ok {
		fmt.eprintln("Standard rotation pool test failed")
		return false
	}

	zone_a := shared.Object{
		active = true,
		objective = true,
		collision_type = .BOX,
		position = {0, 0, 0},
		scale = {20, 10, 20},
	}
	zone_b := shared.Object{
		active = true,
		objective = true,
		collision_type = .BOX,
		position = {100, 0, 0},
		scale = {20, 10, 20},
	}
	map_inst := shared.Map{death_y = -100}
	append(&map_inst.objects, &zone_a, &zone_b)
	defer delete(map_inst.objects)

	config := shared.DEFAULT_GAME_CONFIG
	config.game_time = 1
	config.score_limit = 100
	config.objective_rotation_time = 2
	config.objective_score_rate = 2
	config.regen_delay = 0.5
	config.respawn_delay = 0.5

	game := shared.Game{}
	maps := []^shared.Map{&map_inst}
	shared.game_configure(&game, &config, maps, nil, nil, nil)
	shared.game_init(&game, 0, 0, true)
	defer shared.game_destroy(&game)

	if len(game.objective_indices) != 2 || game.match.objective.active_object_index != 0 {
		fmt.eprintln("Objective discovery test failed")
		return false
	}

	player_one := shared.player_init(&game)
	player_two := shared.player_init(&game)
	player_one.team = 1
	player_two.team = 2
	shared.game_players_add(&game, player_one)
	shared.game_players_add(&game, player_two)
	shared.player_spawn(player_one)
	shared.player_spawn(player_two)
	player_one.position = {0, 0, 0}
	player_two.position = {50, 0, 0}

	shared.game_tick(&game, 0.5, 0.5)
	if game.match.team_scores[1] != 1 || game.match.objective.owner_team != 1 || game.match.objective.contested {
		fmt.eprintln("Objective scoring test failed")
		return false
	}

	player_two.position = {0, 0, 0}
	shared.game_tick(&game, 1.0, 0.5)
	if game.match.team_scores[1] != 1 || !game.match.objective.contested {
		fmt.eprintln("Objective contest test failed")
		return false
	}

	player_two.position = {50, 0, 0}
	shared.game_tick(&game, 2.1, 1.1)
	if game.match.objective.active_zone != 1 || game.match.objective.active_object_index != 1 {
		fmt.eprintln("Objective rotation test failed")
		return false
	}

	player_one.health = 100
	if !shared.player_apply_damage(player_one, player_two, 25, 1, false) || player_one.health != 75 {
		fmt.eprintln("Player damage test failed")
		return false
	}
	shared.game_tick(&game, 2.3, 0.2)
	if player_one.health != 75 {
		fmt.eprintln("Regeneration delay test failed")
		return false
	}
	shared.game_tick(&game, 3.0, 0.7)
	if player_one.health <= 75 {
		fmt.eprintln("Regeneration test failed")
		return false
	}

	shared.player_apply_damage(player_one, player_two, 1000, 1, true)
	if player_one.active || player_one.deaths != 1 || player_two.kills != 1 {
		fmt.eprintln("Death accounting test failed")
		return false
	}
	shared.game_tick(&game, 3.6, 0.6)
	if !player_one.active || player_one.health != f32(player_one.max_health) {
		fmt.eprintln("Automatic respawn test failed")
		return false
	}

	// Exercise the real hitscan path. The active objective volume sits between
	// the players and must not behave like an invisible bullet-blocking wall.
	player_two.position = {-10, 0, 0}
	player_two.direction = {0, -1.5707963}
	player_one.position = {10, 0, 0}
	player_one.health = f32(player_one.max_health)
	health_before_shot := player_one.health
	shot_seq_before := player_two.shot_seq
	recoil_before := player_two.recoil_force
	shared.player_shoot(player_two)
	if player_one.health >= health_before_shot ||
	   player_two.shot_seq != shot_seq_before + 1 ||
	   player_two.recoil_force <= recoil_before {
		fmt.eprintln("Authoritative player hitscan test failed")
		return false
	}

	state := shared.packet_match_state_from_game(&game)
	buf: [128]byte
	packet_size := shared.packet_serialize_match_state(buf[:], &state)
	decoded, decoded_ok := shared.packet_deserialize_match_state(buf[:packet_size])
	if !decoded_ok || decoded.active_zone != state.active_zone || decoded.team1_score != state.team1_score || decoded.time_remaining != state.time_remaining {
		fmt.eprintln("Match-state packet round-trip test failed")
		return false
	}
	initial_time := game.match.time_remaining
	shared.game_tick(&game, 4.0, 1.0)
	if game.match.time_remaining != initial_time - 1.0 {
		fmt.eprintln("Authoritative match timer tick test failed")
		return false
	}

	player_state := shared.Packet_Player_State{
		player_id = 7,
		active = true,
		is_you = true,
		team = 2,
		class_id = 6,
		position = {1, 2, 3},
		velocity = {4, 5, 6},
		x_dir = 0.25,
		y_dir = 0.5,
		on_ground = true,
		on_ramp = true,
		did_jump = true,
		can_slide = true,
		on_wall = 3,
		crouch_val = 0.25,
		aim_val = 0.75,
		slide_timer = 0.2,
		jump_timer = 0.3,
		health = 72.5,
		max_health = 90,
		weapon_id = 7,
		active_ammo = 5,
		shot_seq = 17,
		ack_seq = 42,
	}
	player_packet_size := shared.packet_serialize_state(buf[:], &player_state)
	header_payload_size, _ := endian.get_u16(buf[5:7], .Little)
	wire_ammo, _ := endian.get_u32(buf[80:84], .Little)
	wire_shot_seq, _ := endian.get_u32(buf[84:88], .Little)
	wire_ack, _ := endian.get_i32(buf[88:92], .Little)
	if player_packet_size != 92 || header_payload_size != shared.PACKET_PLAYER_STATE_PAYLOAD_SIZE || buf[79] != player_state.weapon_id || wire_ammo != player_state.active_ammo || wire_shot_seq != player_state.shot_seq || wire_ack != player_state.ack_seq {
		fmt.eprintln("Player-state fixed wire layout test failed")
		return false
	}
	decoded_player, decoded_player_ok := shared.packet_deserialize_state(buf[:player_packet_size])
	if !decoded_player_ok || decoded_player != player_state {
		fmt.eprintln("Player-state packet round-trip test failed")
		return false
	}
	if _, malformed_ok := shared.packet_deserialize_state(buf[:player_packet_size - 4]); malformed_ok {
		fmt.eprintln("Truncated player-state rejection test failed")
		return false
	}

	impact := shared.Bullet_Impact{
		position = {1.25, -2.5, 3.75},
		normal = {0, 0, 1},
	}
	impact_packet_size := shared.packet_serialize_bullet_impact(buf[:], &impact)
	decoded_impact, decoded_impact_ok := shared.packet_deserialize_bullet_impact(buf[:impact_packet_size])
	if !decoded_impact_ok ||
	   impact_packet_size != shared.PACKET_HEADER_SIZE + shared.PACKET_BULLET_IMPACT_PAYLOAD_SIZE ||
	   decoded_impact != impact {
		fmt.eprintln("Bullet-impact packet round-trip test failed")
		return false
	}
	if _, malformed_impact_ok := shared.packet_deserialize_bullet_impact(buf[:impact_packet_size - 1]); malformed_impact_ok {
		fmt.eprintln("Truncated bullet-impact rejection test failed")
		return false
	}

	connect_size := shared.packet_serialize_connect(buf[:], 6)
	connect_class, connect_version, connect_ok := shared.packet_deserialize_connect(buf[:connect_size])
	if !connect_ok || connect_size != 13 || connect_class != 6 || connect_version != shared.PROTOCOL_VERSION {
		fmt.eprintln("Protocol-version handshake test failed")
		return false
	}

	fmt.println("Objective/combat state tests OK")
	return true
}
