package shared

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"

// Official GAPI map IDs 0-46, matching download_maps.py.
DEFAULT_MAP_NAMES := [?]string{
	"burg", // 0
	"littletown", // 1
	"sandstorm", // 2
	"subzero", // 3
	"undergrowth", // 4
	"shipment", // 5
	"freight", // 6
	"lostworld", // 7
	"citadel", // 8
	"oasis", // 9
	"kanji", // 10
	"industry", // 11
	"lumber", // 12
	"evacuation", // 13
	"site", // 14
	"skytemple", // 15
	"lagoon", // 16
	"bureau", // 17
	"tortuga", // 18
	"tropicano", // 19
	"krunk_plaza", // 20
	"arena", // 21
	"habitat", // 22
	"atomic", // 23
	"old_burg", // 24
	"throwback", // 25
	"stockade", // 26
	"facility", // 27
	"clockwork", // 28
	"laboratory", // 29
	"shipyard", // 30
	"soul_sanctum", // 31
	"bazaar", // 32
	"erupt", // 33
	"hq", // 34
	"khepri", // 35
	"lush", // 36
	"vivo", // 37
	"slide_moonlight", // 38
	"eterno_simulator", // 39
	"stalk_factory", // 40
	"eterno_jump", // 41
	"frontier", // 42
	"bastion", // 43
	"piazza", // 44
	"barnyard", // 45
	"candy_heist", // 46
}

// Standard rotation intentionally stays smaller than the complete map registry.
// Excluded maps remain available through --map and custom server configuration.
ROTATION_MAPS := [?]int{0, 2, 4, 3, 11, 14, 17, 42}
ROTATION_MODES := [?]i32{0}

// Browser surface texture registry, in `t` order. `tv` is an index into
// that texture's variants array, not an arbitrary filename suffix. Model
// prefab skins have their own registry and do not use this table.
MAP_TEXTURE_VARIANT_COUNTS := [?]i32{8, 4, 4, 1, 3, 1, 3, 3, 4, 1, 3, 11, 3, 4, 3, 4, 4, 2, 3, 1}

map_texture_variant :: proc(texture_id, requested: i32) -> i32 {
	if texture_id < 0 || int(texture_id) >= len(MAP_TEXTURE_VARIANT_COUNTS) { return 0 }
	if requested <= 0 || requested >= MAP_TEXTURE_VARIANT_COUNTS[texture_id] { return 0 }
	return requested
}

// Sandstorm uses the refreshed API map under the existing v3 asset filename.
map_asset_name :: proc(name: string) -> string {
	if name == "sandstorm" || name == "ss_v3" {
		return "sandstorm_v3"
	}
	return name
}

DEFAULT_MAP_CONFIG := Map_Config {
	cam_type      = .NORMAL,
	cam_rotation  = true,
	cam_offset    = Vec3{0, 0, 0},
	model         = .NORMAL,
	speed         = Vec3{1.0, 1.0, 1.0},
	ladder_accel  = 1.0,
	air_accel     = 1.0,
	slide_time    = 1.0,
	slide_accel   = 1.0,
	jump_cooldown = 1.0,
	infinite_jump = false,
}

g_maps: [len(DEFAULT_MAP_NAMES)]^Map
g_maps_loaded: bool

load_default_maps :: proc() {
	if g_maps_loaded {
		return
	}

	g_maps_loaded = true
}

load_default_map :: proc(index: int) -> ^Map {
	if index < 0 || index >= len(DEFAULT_MAP_NAMES) {
		return nil
	}
	if g_maps[index] != nil {
		return g_maps[index]
	}

	path := strings.concatenate({assets_path(), "maps/", map_asset_name(DEFAULT_MAP_NAMES[index]), ".json"})
	defer delete(path)

	map_inst, ok := map_load_from_file(path)
	if !ok {
		return nil
	}

	g_maps[index] = map_inst
	return map_inst
}

unload_default_maps :: proc() {
	if !g_maps_loaded {
		return
	}

	for &map_inst in g_maps {
		if map_inst != nil {
			map_destroy(map_inst)
			map_inst = nil
		}
	}

	g_maps_loaded = false
}

// Loads and parses a Krunker map JSON into a Map. Returns nil on failure.
map_load_from_file :: proc(filename: string) -> (map_ptr: ^Map, ok: bool) {
	data, err := os.read_entire_file_from_path(filename, context.allocator)
	if err != nil {
		fmt.eprintf("Failed to read map file: %s\n", filename)
		return nil, false
	}
	defer delete(data)

	json_val, parse_err := json.parse_string(string(data))
	if parse_err != .None {
		fmt.eprintf("Failed to parse JSON map file %s: %v\n", filename, parse_err)
		return nil, false
	}

	root, is_obj := json_val.(json.Object)
	if !is_obj {
		json.destroy_value(json_val)
		return nil, false
	}

	objects_val, has_objects := root["objects"]
	spawns_val, has_spawns := root["spawns"]

	objects_arr, objects_ok := objects_val.(json.Array)
	spawns_arr, spawns_ok := spawns_val.(json.Array)

	if !has_objects || !objects_ok || !has_spawns || !spawns_ok {
		json.destroy_value(json_val)
		return nil, false
	}

	colors_val, has_colors := root["colors"]
	colors_arr, colors_ok := colors_val.(json.Array)
	parsed_colors := make([]Vec4, colors_ok ? len(colors_arr) : 0)

	// Newer exported maps intern object scale triples in a root-level `xyz`
	// array and store the triple index in each object's `si` field.
	xyz_val, has_xyz := root["xyz"]
	xyz_arr, xyz_ok := xyz_val.(json.Array)

	if has_colors && colors_ok {
		for i in 0 ..< len(colors_arr) {
			color := Vec4{1.0, 1.0, 1.0, 1.0}

			if hex, is_str := colors_arr[i].(json.String); is_str {
				parse_hex_color(hex, &color)
			}

			parsed_colors[i] = color
		}
	}

	map_inst := new(Map)
	map_inst.config = DEFAULT_MAP_CONFIG
	// Parse the stable environment fields before retaining the complete map
	// object. Older maps omit most fields and naturally use browser defaults.
	map_inst.lighting, _ = lighting_parse_json(json_val)
	if override_path := lighting_map_override_path(filename); len(override_path) > 0 {
		if override, override_ok := lighting_load_from_file(override_path); override_ok {
			map_inst.lighting = override
		}
	}
	map_inst.death_y = GAME_CONSTANTS.death_y
	map_inst.raw_data = json_val
	map_inst.colors = parsed_colors[:]

	if dth, has_dth := root["dthY"]; has_dth {
		#partial switch v in dth {
		case json.Float:
			map_inst.death_y = f32(v)
		case json.Integer:
			map_inst.death_y = f32(v)
		}
	}

	if cam, has_cam := root["camPos"]; has_cam {
		if arr, is_arr := cam.(json.Array); is_arr && len(arr) >= 3 {
			map_inst.camera_position.x = get_json_f32(arr[0])
			map_inst.camera_position.y = get_json_f32(arr[1])
			map_inst.camera_position.z = get_json_f32(arr[2])
		}
	}

	// Spawns
	for sp_val in spawns_arr {
		sp_arr, is_sp_arr := sp_val.(json.Array)
		if !is_sp_arr || len(sp_arr) < 3 {
			continue
		}

		spawn := new(Spawn)
		spawn.position.x = get_json_f32(sp_arr[0])
		spawn.position.y = get_json_f32(sp_arr[1])
		spawn.position.z = get_json_f32(sp_arr[2])

		if len(sp_arr) >= 4 {
			spawn.team = i32(get_json_f32(sp_arr[3]))
		}
		if len(sp_arr) >= 5 {
			spawn.direction = i32(get_json_f32(sp_arr[4]))
		}
		if len(sp_arr) >= 6 {
			spawn.comp = i32(get_json_f32(sp_arr[5]))
		}

		append(&map_inst.spawns, spawn)
	}

	// Objects
	for obj_val in objects_arr {
		raw_obj, is_obj_dict := obj_val.(json.Object)
		if !is_obj_dict {
			continue
		}

		pos_val, has_pos := raw_obj["p"]

		if !has_pos {
			continue
		}

		pos_arr, p_ok := pos_val.(json.Array)
		if !p_ok || len(pos_arr) < 3 {
			continue
		}

		scale := Vec3{}
		scale_ok := false

		if scale_val, has_scale := raw_obj["s"]; has_scale {
			if scale_arr, s_ok := scale_val.(json.Array); s_ok && len(scale_arr) >= 3 {
				scale.x = get_json_f32(scale_arr[0])
				scale.y = get_json_f32(scale_arr[1])
				scale.z = get_json_f32(scale_arr[2])
				scale_ok = true
			}
		} else if si_val, has_si := raw_obj["si"]; has_si && has_xyz && xyz_ok {
			scale_index := int(get_json_f32(si_val)) * 3
			if scale_index >= 0 && scale_index + 2 < len(xyz_arr) {
				scale.x = get_json_f32(xyz_arr[scale_index])
				scale.y = get_json_f32(xyz_arr[scale_index + 1])
				scale.z = get_json_f32(xyz_arr[scale_index + 2])
				scale_ok = true
			}
		}

		if !scale_ok {
			continue
		}

		prefab_id: i32 = 0
		if i_val, has_i := raw_obj["i"]; has_i {
			prefab_id = i32(get_json_f32(i_val))
		} else if id_val, has_id := raw_obj["id"]; has_id {
			prefab_id = i32(get_json_f32(id_val))
		}

		obj := new(Object)
		obj.active = true
		obj.raw_data = raw_obj
		obj.position.x = get_json_f32(pos_arr[0])
		obj.position.y = get_json_f32(pos_arr[1])
		obj.position.z = get_json_f32(pos_arr[2])

		obj.scale = scale

		obj.prefab = Prefab(prefab_id)
		if team_val, has_team := raw_obj["tm"]; has_team {
			obj.team = u32(max(0, i32(get_json_f32(team_val))))
		}
		if score_val, has_score := raw_obj["score"]; has_score {
			obj.score_points = u32(max(0, i32(get_json_f32(score_val))))
		}

		if t_val, has_t := raw_obj["t"]; has_t {
			obj.texture = u32(get_json_f32(t_val))
		} else if obj.prefab == .LADDER {
			obj.texture = 2
		}
		if tv_val, has_tv := raw_obj["tv"]; has_tv && json_is_number(tv_val) {
			obj.texture_variant = i32(get_json_f32(tv_val))
		}
		// Current map exports encode visible cube faces as a hexadecimal bit mask
		// in `f`. Missing faces are intentionally omitted to avoid drawing hidden
		// sides of adjacent blocks.
		obj.face_mask = 0x3f
		if f_val, has_f := raw_obj["f"]; has_f {
			#partial switch v in f_val {
			case json.String:
				obj.face_mask = map_face_mask_native(parse_hex_u32(string(v)))
			case json.Integer:
				obj.face_mask = map_face_mask_native(u32(max(0, i32(v))))
			case json.Float:
				obj.face_mask = map_face_mask_native(u32(max(0, i32(v))))
			}
		}

		if prefab_id == i32(Prefab.BOOST_PAD) {
			obj.jump_pad = true
			obj.bounce = get_json_f32(raw_obj["bm"] if "bm" in raw_obj else nil)
			obj.crouch = !("cr" in raw_obj) || is_nullish(raw_obj["cr"])

			if obj.bounce == 0.0 {
				obj.bounce = 1.0
			}
		}

		dir_val, has_dir := raw_obj["d"]
		obj.direction = has_dir ? u8(i32(get_json_f32(dir_val)) % 4) : 0

		if prefab_id == i32(Prefab.LADDER) {
			obj.ladder = true

			direction := math.PI * 0.5 * f32(obj.direction)
			obj.position.x += GAME_CONSTANTS.ladder_scale * math.cos(direction)
			obj.position.z += GAME_CONSTANTS.ladder_scale * math.sin(direction)

			if obj.direction % 2 == 1 {
				obj.scale.x = GAME_CONSTANTS.ladder_width * 2.0
				obj.scale.z = GAME_CONSTANTS.ladder_scale * 2.0
			} else {
				obj.scale.x = GAME_CONSTANTS.ladder_scale * 2.0
				obj.scale.z = GAME_CONSTANTS.ladder_width * 2.0
			}
		}

		if prefab_id == i32(Prefab.RAMP) {
			ramp := new(Ramp)
			ramp.boost = get_json_f32(raw_obj["b"] if "b" in raw_obj else nil)

			ramp.start.x = obj.position.x
			ramp.start.y = obj.position.z
			ramp.end.x = obj.position.x
			ramp.end.y = obj.position.z

			if obj.direction % 2 == 1 {
				mlt: f32 = obj.direction < 2 ? 1.0 : -1.0
				ramp.start.y -= obj.scale.z * 0.5 * mlt
				ramp.end.y += obj.scale.z * 0.5 * mlt
			} else {
				mlt: f32 = obj.direction < 2 ? 1.0 : -1.0
				ramp.start.x -= obj.scale.x * 0.5 * mlt
				ramp.end.x += obj.scale.x * 0.5 * mlt
			}

			obj.ramp = ramp
		}

		l_val, has_l := raw_obj["l"]
		col_val, has_col := raw_obj["col"]
		bo_val, has_bo := raw_obj["bo"]

		// Visibility (`v`) is independent of collision. Maps use hidden blocks
		// as solid collision volumes beneath non-colliding decorative meshes.
		// The browser derives noCol from `l` / `col`, never from `v`.
		no_collisions := (has_l && !is_nullish(l_val) && (!json_is_number(l_val) || get_json_f32(l_val) != 0)) ||
		                 (has_col && !is_nullish(col_val) && (!json_is_number(col_val) || get_json_f32(col_val) != 0))
		is_border := has_bo && !is_nullish(bo_val) && (!json_is_number(bo_val) || get_json_f32(bo_val) != 0)

		switch prefab_id {
		case i32(Prefab.CUBE), i32(Prefab.GATE), i32(Prefab.DEPOSIT_BOX), i32(Prefab.PREMIUM_ZONE), i32(Prefab.VERIFIED_ZONE), i32(Prefab.TEAM_ZONE):
			obj.is_border = is_border
		}

		switch prefab_id {
		case i32(Prefab.SPHERE), i32(Prefab.POINT_LIGHT), i32(Prefab.LIGHT_CONE), i32(Prefab.SOUND_EMITTER), i32(Prefab.PARTICLES), i32(Prefab.LIQUID), i32(Prefab.SPECTATE_CAM), i32(Prefab.EVENT):
			obj.collision_type = .NONE
		case i32(Prefab.GATE), i32(Prefab.TRIGGER), i32(Prefab.TERMINAL), i32(Prefab.DEPOSIT_BOX), i32(Prefab.OBJECTIVE), i32(Prefab.BOMB_SITE), i32(Prefab.FLAG), i32(Prefab.WEAPON_PICKUP), i32(Prefab.SHOWCASE), i32(Prefab.RAMP), i32(Prefab.PREMIUM_ZONE), i32(Prefab.VERIFIED_ZONE), i32(Prefab.SCORE_ZONE), i32(Prefab.DEATH_ZONE), i32(Prefab.CHECK_POINT), i32(Prefab.TELEPORTER), i32(Prefab.LADDER):
			obj.collision_type = .BOX
		case:
			if prefab_id < 0 || prefab_id > i32(Prefab.KNIGHT) {
				obj.collision_type = .NONE
			} else if no_collisions {
				obj.collision_type = .NONE
			} else if prefab_id == i32(Prefab.CYLINDER) {
				obj.collision_type = .CYLINDER
			} else {
				obj.collision_type = .BOX
			}
		}

		switch prefab_id {
		case i32(Prefab.BOT), i32(Prefab.TELEPORTER), i32(Prefab.CHECK_POINT), i32(Prefab.DEATH_ZONE), i32(Prefab.SCORE_ZONE), i32(Prefab.TEAM_ZONE), i32(Prefab.VERIFIED_ZONE), i32(Prefab.RAMP), i32(Prefab.SPECTATE_CAM), i32(Prefab.SIGN), i32(Prefab.LIQUID), i32(Prefab.PARTICLES), i32(Prefab.SHOWCASE), i32(Prefab.WEAPON_PICKUP), i32(Prefab.FLAG), i32(Prefab.BOMB_SITE), i32(Prefab.OBJECTIVE), i32(Prefab.SOUND_EMITTER), i32(Prefab.LIGHT_CONE), i32(Prefab.POINT_LIGHT):
			obj.wall_jumpable = false
		case:
			wj, has_wj := raw_obj["wj"]
			obj.wall_jumpable = !has_wj || is_nullish(wj)
		}

		switch prefab_id {
		case i32(Prefab.VERIFIED_ZONE):
			obj.verified = true
		case i32(Prefab.PREMIUM_ZONE):
			obj.premium = true
		case i32(Prefab.SCORE_ZONE):
			obj.score_zone = true
		case i32(Prefab.TEAM_ZONE):
			obj.team_zone = true
		case i32(Prefab.TELEPORTER):
			obj.teleporter = true
		case i32(Prefab.CHECK_POINT):
			obj.checkpoint = true
		case i32(Prefab.WEAPON_PICKUP):
			obj.pickup = true
		case i32(Prefab.FLAG):
			obj.flag = true
		case i32(Prefab.TRIGGER):
			obj.trigger = true
		case i32(Prefab.DEATH_ZONE):
			obj.kill = true
		case i32(Prefab.OBJECTIVE):
			obj.objective = true
		case i32(Prefab.BOMB_SITE):
			obj.bomb_site = true
		}

		// Dimensions
		if obj.position.x - obj.scale.x * 0.5 < map_inst.min_dim.x {
			map_inst.min_dim.x = obj.position.x - obj.scale.x * 0.5
		} else if obj.position.x + obj.scale.x * 0.5 > map_inst.max_dim.x {
			map_inst.max_dim.x = obj.position.x + obj.scale.x * 0.5
		}

		if obj.position.y - obj.scale.y * 0.5 < map_inst.min_dim.y {
			map_inst.min_dim.y = obj.position.y - obj.scale.y * 0.5
		} else if obj.position.y + obj.scale.y * 0.5 > map_inst.max_dim.y {
			map_inst.max_dim.y = obj.position.y + obj.scale.y * 0.5
		}

		if obj.position.z - obj.scale.z * 0.5 < map_inst.min_dim.z {
			map_inst.min_dim.z = obj.position.z - obj.scale.z * 0.5
		} else if obj.position.z + obj.scale.z * 0.5 > map_inst.max_dim.z {
			map_inst.max_dim.z = obj.position.z + obj.scale.z * 0.5
		}

		append(&map_inst.objects, obj)
	}

	return map_inst, true
}

// NOTE: client-side only — populates textures/geometry for each object's mesh.
// The callback is invoked from the client (prefab_init) since shared has no GL.
map_load_meshes :: proc(map_inst: ^Map, prefab_init_fn: proc(^Object, []Vec4, json.Value) -> rawptr) {
	for obj in map_inst.objects {
		obj.mesh = prefab_init_fn(obj, map_inst.colors, obj.raw_data)
	}
}

map_reset :: proc(map_inst: ^Map) {
	// NOTE: static maps currently; objects are not reset between rounds.
}

map_destroy :: proc(map_inst: ^Map) {
	if map_inst == nil {
		return
	}

	for s in map_inst.spawns {
		free(s)
	}
	delete(map_inst.spawns)

	for o in map_inst.objects {
		if o.tex_anim != nil {
			free(o.tex_anim)
		}
		if o.ramp != nil {
			free(o.ramp)
		}
		free(o)
	}
	delete(map_inst.objects)

	delete(map_inst.colors)

	json.destroy_value(map_inst.raw_data)

	free(map_inst)
}

get_json_f32 :: proc(val: json.Value) -> f32 {
	#partial switch v in val {
	case json.Float:
		return f32(v)
	case json.Integer:
		return f32(v)
	case json.String:
		value, ok := strconv.parse_f32(v)
		return value if ok else 0.0
	}

	return 0.0
}

json_is_number :: proc(val: json.Value) -> bool {
	#partial switch v in val {
	case json.Float, json.Integer:
		return true
	}

	return false
}

parse_hex_u32 :: proc(value: string) -> u32 {
	result: u32 = 0
	for ch in value {
		digit: u32
		switch ch {
		case '0'..='9': digit = u32(ch - '0')
		case 'a'..='f': digit = u32(ch - 'a') + 10
		case 'A'..='F': digit = u32(ch - 'A') + 10
		case: continue
		}
		result = (result << 4) | digit
	}
	return result
}

// Browser face order is +X, -X, +Y, -Y, +Z, -Z. Native cube geometry is
// front(+Z), back(-Z), left(-X), right(+X), top(+Y), bottom(-Y).
map_face_mask_native :: proc(raw: u32) -> u32 {
	return (((raw >> 1) & 1) << 0) |
		(((raw >> 0) & 1) << 1) |
		(((raw >> 4) & 1) << 2) |
		(((raw >> 5) & 1) << 3) |
		(((raw >> 3) & 1) << 4) |
		(((raw >> 2) & 1) << 5)
}

is_nullish :: proc(val: json.Value) -> bool {
	#partial switch v in val {
	case json.Null:
		return true
	}

	return false
}
