package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

import shared "../shared"

EPSILON :: 1e-3

Tick :: struct {
	input:    shared.Input,
	expected: Player_State,
}

Player_State :: struct {
	position: shared.Vec3,
	velocity: shared.Vec3,
	ramp_fix: ^f32,
}

get_num :: proc(val: json.Value) -> f32 {
	#partial switch v in val {
	case json.Float:
		return f32(v)
	case json.Integer:
		return f32(v)
	}

	return 0.0
}

parse_tick :: proc(raw: json.Value) -> (tick: Tick, ok: bool) {
	arr, is_arr := raw.(json.Array)
	if !is_arr || len(arr) < 2 {
		return {}, false
	}

	raw_input, is_input_arr := arr[0].(json.Array)
	raw_state, is_state_arr := arr[1].(json.Array)

	if !is_input_arr || len(raw_input) < 7 || !is_state_arr || len(raw_state) < 7 {
		return {}, false
	}

	tick.input.delta = get_num(raw_input[0]) / 1000.0
	tick.input.y_dir = get_num(raw_input[1]) / 1000.0
	tick.input.x_dir = get_num(raw_input[2]) / 1000.0

	move_dir := i32(get_num(raw_input[3]))
	tick.input.jump = get_num(raw_input[4]) != 0
	tick.input.crouch = get_num(raw_input[5]) != 0
	tick.input.scope = get_num(raw_input[6]) != 0

	if move_dir != -1 {
		move_dir += 7
	}

	tick.input.move_dir = move_dir

	tick.expected.position.x = get_num(raw_state[0])
	tick.expected.position.y = get_num(raw_state[1])
	tick.expected.position.z = get_num(raw_state[2])
	tick.expected.velocity.x = get_num(raw_state[3])
	tick.expected.velocity.y = get_num(raw_state[4])
	tick.expected.velocity.z = get_num(raw_state[5])

	// ramp_fix is the 7th element (can be null)
	if is_num(raw_state[6]) {
		tick.expected.ramp_fix = new(f32)
		tick.expected.ramp_fix^ = get_num(raw_state[6])
	}

	return tick, true
}

is_num :: proc(val: json.Value) -> bool {
	#partial switch v in val {
	case json.Float, json.Integer:
		return true
	}

	return false
}

validate_tick :: proc(player: ^shared.Player, expected: ^Player_State, tick_index: int) -> bool {
	dx := player.position.x - expected.position.x
	dy := player.position.y - expected.position.y
	dz := player.position.z - expected.position.z

	x_bad := abs(dx) > EPSILON
	y_bad := abs(dy) > EPSILON
	z_bad := abs(dz) > EPSILON

	dvx := player.velocity.x - expected.velocity.x
	dvy := player.velocity.y - expected.velocity.y
	dvz := player.velocity.z - expected.velocity.z

	vx_bad := abs(dvx) > EPSILON
	vy_bad := abs(dvy) > EPSILON
	vz_bad := abs(dvz) > EPSILON

	ramp_bad :=
		(expected.ramp_fix != nil) != (player.ramp_fix != nil) ||
		(expected.ramp_fix != nil &&
				player.ramp_fix != nil &&
				abs(player.ramp_fix^ - expected.ramp_fix^) > EPSILON)

	bad := x_bad || y_bad || z_bad || vx_bad || vy_bad || vz_bad || ramp_bad

	if bad {
		fmt.printf("Failed at tick #%d!\n", tick_index)

		print_field("x", expected.position.x, player.position.x)
		print_field("y", expected.position.y, player.position.y)
		print_field("z", expected.position.z, player.position.z)
		print_field("vel_x", expected.velocity.x, player.velocity.x)
		print_field("vel_y", expected.velocity.y, player.velocity.y)
		print_field("vel_z", expected.velocity.z, player.velocity.z)

		if expected.ramp_fix != nil {
			print_field(
				"ramp_fix",
				expected.ramp_fix^,
				player.ramp_fix != nil ? player.ramp_fix^ : 0.0,
			)
		}
	}

	return !bad
}

print_field :: proc(name: string, expected, actual: f32) {
	delta := actual - expected
	fmt.printf(
		"| %-15s | expected %-15.6f | actual %-15.6f | delta %-15.6f |\n",
		name,
		expected,
		actual,
		delta,
	)
}

test_ray_box_hit :: proc() -> bool {
	origin := shared.Vec3{0, 1, 5}
	direction := shared.Vec3{0, 0, -10}

	t, normal, hit := shared.ray_box_hit(
		origin,
		direction,
		shared.Vec3{0, 0, 0},
		shared.Vec3{2, 2, 2},
	)

	ok := hit && abs(t - 0.4) <= EPSILON && normal == shared.Vec3{0, 0, 1}
	if ok {
		fmt.println("Ray/AABB impact test OK")
	} else {
		fmt.printf("Ray/AABB impact test failed: hit=%v t=%f normal=%v\n", hit, t, normal)
	}

	return ok
}

test_loadout :: proc(player: ^shared.Player, class_index, sidearm, melee: i32) {
	shared.player_spawn(player, class_index)

	has_primary := false
	has_sidearm := false
	has_melee := false

	for i in 0 ..< player.loadout_size {
		weapon_id := player.loadout[i]
		weapon := shared.g_weapons()[weapon_id]

		if weapon.secondary {
			has_sidearm = true
		}
		if weapon.melee {
			has_melee = true
		}
		if weapon_id != sidearm && weapon_id != melee {
			has_primary = true
		}
	}

	if !has_primary || !has_sidearm || !has_melee {
		fmt.printf(
			"Loadout composition test failed for class %d: primary=%v sidearm=%v melee=%v loadout=%v\n",
			class_index,
			has_primary,
			has_sidearm,
			has_melee,
			player.loadout,
		)
		os.exit(1)
	}

	fmt.println("Loadout composition test OK")
}

run_test :: proc(name: string, player: ^shared.Player) {
	path := fmt.tprintf("%ssrc/tests/inputs/%s", project_root(), name)
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)

	if err != nil {
		fmt.printf("Failed to parse %s, skipping...\n", name)
		return
	}

	json_val, parse_err := json.parse_string(string(data))
	if parse_err != .None {
		fmt.printf("Failed to parse %s, skipping...\n", name)
		return
	}
	defer json.destroy_value(json_val)

	ticks_arr, arr_ok := json_val.(json.Array)
	if !arr_ok {
		fmt.printf("Failed to parse %s, skipping...\n", name)
		return
	}

	tick_count := len(ticks_arr)
	ticks := make([]Tick, tick_count)
	defer delete(ticks)

	fmt.printf("Running test %s (%d ticks)...\n", name, tick_count)

	for i in 0 ..< tick_count {
		tick, ok := parse_tick(ticks_arr[i])
		if !ok {
			fmt.printf("Failed to parse tick #%d!\n", i)
			return
		}

		ticks[i] = tick
	}

	shared.player_spawn(player)

	player.position = ticks[0].expected.position
	player.wall_jump = name == "wall_jump.json"

	for i in 0 ..< tick_count {
		if !validate_tick(player, &ticks[i].expected, i) {
			return
		}

		shared.player_proc_input(player, &ticks[i].input, false, false)
	}

	fmt.println("Test OK")
}

project_root :: proc() -> string {
	wd, err := os.get_working_directory(context.temp_allocator)
	if err != nil {
		return "./"
	}

	if strings.has_suffix(wd, "/cmake-build-debug") ||
	   strings.has_suffix(wd, "/cmake-build-release") ||
	   strings.has_suffix(wd, "/bin") {
		return "../"
	}

	return "./"
}

main :: proc() {
	if !test_net_send_queue() {
		os.exit(1)
	}
	if !test_snapshot_interpolation() {
		os.exit(1)
	}
	if !test_gameplay_config() {
		os.exit(1)
	}
	if !test_configured_weapon_switch() {
		os.exit(1)
	}
	if !test_server_physics() {
		os.exit(1)
	}
	if !test_client_physics() {
		os.exit(1)
	}
	if !test_famas_burst() {
		os.exit(1)
	}
	if !test_shot_feedback() {
		os.exit(1)
	}
	if !test_objective_combat_state() {
		os.exit(1)
	}
	fmt.println()

	ss_v3_path := fmt.tprintf("%sassets/maps/sandstorm_v3.json", project_root())
	if ss_v3, ss_v3_ok := shared.map_load_from_file(ss_v3_path); !ss_v3_ok || len(ss_v3.objects) != 1362 {
		fmt.eprintf("sandstorm_v3 compact scale table test failed\n")
		os.exit(1)
	} else {
		out_of_range_non_colliding := true
		for obj in ss_v3.objects {
			if i32(obj.prefab) > i32(shared.Prefab.KNIGHT) && obj.collision_type != shared.Collision_Type.NONE {
				out_of_range_non_colliding = false
				break
			}
		}
		shared.map_destroy(ss_v3)
		if !out_of_range_non_colliding {
			fmt.eprintf("sandstorm_v3 out-of-range prefab collision test failed\n")
			os.exit(1)
		}
		fmt.println("sandstorm_v3 compact scale table test OK")
	}
	fmt.println()

	if !test_ray_box_hit() {
		os.exit(1)
	}
	fmt.println()

	tests := []string {
		"collide.json",
		"crouch.json",
		"jump.json",
		"scope.json",
		"slide.json",
		"spawn.json",
		"walk_forwards.json",
		"walk_ladder.json",
		"walk_ramp.json",
		"wall_jump.json",
	}

	// NOTE: expects to be run from the repo root so assets/maps/sandstorm.json resolves
	game := shared.Game{}

	sandstorm_path := fmt.tprintf("%sassets/maps/sandstorm.json", project_root())
	sandstorm, map_ok := shared.map_load_from_file(sandstorm_path)

	if !map_ok {
		fmt.println("Failed to load sandstorm!")
		return
	}

	maps := []^shared.Map{sandstorm}

	shared.game_configure(&game, nil, maps, nil, nil, nil)
	shared.game_init(&game, 0, -1, true)

	player := shared.player_init(&game)

	if player == nil {
		fmt.println("Failed to create test player!")
		return
	}

	shared.game_players_add(&game, player)

	// A class with a secondary should spawn with primary + sidearm + melee so
	// weapon switching (Q/E) works. Hunter (class 1) config has secondary=true.
	test_loadout(player, 1, 3, 12)

	for test in tests {
		run_test(test, player)
		fmt.println()
	}

	// kanji jump pad test
	kanji_path := fmt.tprintf("%sassets/maps/kanji.json", project_root())
	kanji, kanji_ok := shared.map_load_from_file(kanji_path)

	if !kanji_ok {
		fmt.println("Failed to load kanji!")
		return
	}

	// NOTE: C test hacks map_count to 0 to avoid freeing; we just reconfigure directly.
	kanji_maps := []^shared.Map{kanji}
	shared.game_configure(&game, nil, kanji_maps, nil, nil, nil)
	shared.game_init(&game, 0, -1, true)

	run_test("kanji_jump_pad.json", player)

}
