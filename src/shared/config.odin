package shared

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

Gameplay_Config :: struct {
	weapons:        []^Weapon,
	classes:        []Class_Config,
	game:           Game_Config,
	arena:          mem.Dynamic_Arena,
	weapon_storage: []Weapon,
	weapons_dir:    string,
	classes_dir:    string,
}

CONFIG_GAME_PATH :: "assets/config/game.toml"

// Section names map config keys to stable weapon indices (WEAPONS_LIST order).
weapon_config_names := [?]string{
	"awp", "ak47", "pistol", "smg", "revolver", "shotgun",
	"lmg", "semi", "rpg", "akimbo", "deagle", "alien", "knife",
}

// Section names map config keys to stable class indices (CLASSES_LIST order).
class_config_names := [?]string{
	"triggerman", "hunter", "run_n_gun", "spray_n_pray", "vince",
	"detective", "marksman", "rocketeer", "agent", "runner",
	"deagler", "bowman", "commando", "trooper",
}

weapon_config_index :: proc(name: string) -> int {
	for n, i in weapon_config_names {
		if n == name {
			return i
		}
	}
	return -1
}

class_config_index :: proc(name: string) -> int {
	for n, i in class_config_names {
		if n == name {
			return i
		}
	}
	return -1
}

// class_config_name returns the config key (e.g. "hunter") for a stable class
// index, or "" when out of range.
class_config_name :: proc(index: int) -> string {
	if index < 0 || index >= len(class_config_names) {
		return ""
	}
	return class_config_names[index]
}

// class_config_name_count returns the number of configured class keys.
class_config_name_count :: proc() -> int {
	return len(class_config_names)
}

// config_load_gameplay returns an owned registry. Its weapon pointers remain stable
// until config_destroy_gameplay is called.
config_load_gameplay :: proc(config_path := CONFIG_GAME_PATH) -> ^Gameplay_Config {
	config := new(Gameplay_Config)
	config.game = DEFAULT_GAME_CONFIG
	mem.dynamic_arena_init(&config.arena)
	allocator := mem.dynamic_arena_allocator(&config.arena)

	config.weapon_storage = make([]Weapon, len(WEAPONS_LIST), allocator)
	config.weapons = make([]^Weapon, len(WEAPONS_LIST), allocator)
	for default_weapon, id in WEAPONS_LIST {
		config.weapon_storage[id] = config_clone_weapon(default_weapon, allocator)
		config.weapons[id] = &config.weapon_storage[id]
	}

	config.classes = make([]Class_Config, len(CLASSES_LIST), allocator)
	for default_class, id in CLASSES_LIST {
		config.classes[id] = config_clone_class(default_class, allocator)
	}

	if len(config_path) > 0 {
		config_load_toml_file(config, config_path)
	}

	return config
}

config_destroy_gameplay :: proc(config: ^Gameplay_Config) {
	if config == nil do return
	mem.dynamic_arena_destroy(&config.arena)
	free(config)
}

config_load_toml_file :: proc(config: ^Gameplay_Config, path: string) -> bool {
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil {
		fmt.eprintf("config: could not read %s\n", path)
		return false
	}
	return config_apply_toml(config, string(data))
}

// config_apply_toml applies partial overrides from a TOML document.
// Expected layout:
//
//	[weapons]
//	weapons-dir = "mods/weapons/"
//
//	[weapons.ak47]
//	name = "Assault Rifle"
//	model = "mods/weapons/model/ak47.obj"
//	sound = "mods/weapons/sounds/ak47_fire.wav"
//	damage = 35.0
//
//	[classes]
//	classes-dir = "mods/classes/"
//
//	[classes.triggerman]
//	loadout = ["ak47", "pistol", "knife"]
//	health = 100
config_apply_toml :: proc(config: ^Gameplay_Config, source: string) -> bool {
	if config == nil do return false

	root, ok := toml_parse(source)
	if !ok {
		fmt.eprintln("config: failed to parse game.toml")
		return false
	}
	defer toml_destroy(root)

	allocator := mem.dynamic_arena_allocator(&config.arena)

	if game_table, has := root.tables["game"]; has {
		config_apply_i32(game_table, "tick_rate", "game", 0, &config.game.tick_rate)
		config_apply_i32(game_table, "max_players", "game", 0, &config.game.max_players)
		config_apply_i32(game_table, "game_time", "game", 0, &config.game.game_time)
		config_apply_f32(game_table, "warmup_time", "game", 0, &config.game.warmup_time)
		config_apply_i32(game_table, "auto_respawn", "game", 0, &config.game.auto_respawn)
		config_apply_i32(game_table, "score_limit", "game", 0, &config.game.score_limit)
		config_apply_bool(game_table, "health_regen", "game", 0, &config.game.health_regen)
		config_apply_f32(game_table, "objective_rotation_time", "game", 0, &config.game.objective_rotation_time)
		config_apply_f32(game_table, "objective_score_rate", "game", 0, &config.game.objective_score_rate)
		config_apply_f32(game_table, "regen_delay", "game", 0, &config.game.regen_delay)
		config_apply_f32(game_table, "respawn_delay", "game", 0, &config.game.respawn_delay)
	}

	if weapons_table, has := root.tables["weapons"]; has {
		if dir, ok := toml_get_string(weapons_table, "weapons-dir"); ok {
			config.weapons_dir = strings.clone(dir, allocator)
		}

		for section_name, section_table in weapons_table.tables {
			id := weapon_config_index(section_name)
			if id < 0 {
				fmt.eprintf("config: unknown weapon section %q\n", section_name)
				continue
			}
			config_apply_weapon(section_table, config.weapons[id], id, allocator)
		}
	}

	if classes_table, has := root.tables["classes"]; has {
		if dir, ok := toml_get_string(classes_table, "classes-dir"); ok {
			config.classes_dir = strings.clone(dir, allocator)
		}

		for section_name, section_table in classes_table.tables {
			id := class_config_index(section_name)
			if id < 0 {
				fmt.eprintf("config: unknown class section %q\n", section_name)
				continue
			}
			config_apply_class(section_table, &config.classes[id], id, allocator)
		}
	}

	return true
}

config_clone_weapon :: proc(source: ^Weapon, allocator: mem.Allocator) -> Weapon {
	result := source^
	result.name = strings.clone(source.name, allocator)
	result.src = strings.clone(source.src, allocator)
	result.icon = strings.clone(source.icon, allocator)
	result.model = strings.clone(source.model, allocator)
	result.texture = strings.clone(source.texture, allocator)
	result.sound = strings.clone(source.sound, allocator)
	result.custom_spread = make([]Vec2, len(source.custom_spread), allocator)
	copy(result.custom_spread, source.custom_spread)
	return result
}

config_clone_class :: proc(source: Class_Config, allocator: mem.Allocator) -> Class_Config {
	result := source
	result.name = strings.clone(source.name, allocator)
	result.texts = make([]string, len(source.texts), allocator)
	for text, i in source.texts {
		result.texts[i] = strings.clone(text, allocator)
	}
	result.loadout = make([]i32, len(source.loadout), allocator)
	copy(result.loadout, source.loadout)
	return result
}

config_warn_field :: proc(kind: string, id: int, field, expected: string) {
	fmt.eprintf("config: %s %d field %s must be %s; keeping default\n", kind, id, field, expected)
}

config_apply_string :: proc(
	table: ^Toml_Table,
	key, kind: string,
	id: int,
	destination: ^string,
	allocator: mem.Allocator,
) {
	if value, ok := toml_get_string(table, key); ok {
		destination^ = strings.clone(value, allocator)
	}
}

config_apply_bool :: proc(table: ^Toml_Table, key, kind: string, id: int, destination: ^bool) {
	if value, ok := toml_get_bool(table, key); ok {
		destination^ = value
	}
}

config_apply_f32 :: proc(table: ^Toml_Table, key, kind: string, id: int, destination: ^f32) {
	if value, ok := toml_get_f32(table, key); ok {
		destination^ = value
	}
}

config_apply_i32 :: proc(table: ^Toml_Table, key, kind: string, id: int, destination: ^i32) {
	if value, ok := toml_get_i64(table, key); ok && value >= i64(min(i32)) && value <= i64(max(i32)) {
		destination^ = i32(value)
	}
}

config_apply_u32 :: proc(table: ^Toml_Table, key, kind: string, id: int, destination: ^u32) {
	if value, ok := toml_get_i64(table, key); ok && value >= 0 && u64(value) <= u64(max(u32)) {
		destination^ = u32(value)
	}
}

config_apply_vec3 :: proc(table: ^Toml_Table, key, kind: string, id: int, destination: ^Vec3) {
	array, ok := toml_get_array(table, key)
	if !ok || len(array) != 3 {
		return
	}

	result: Vec3
	for i in 0 ..< 3 {
		if value, value_ok := toml_array_get_f32(array, i); value_ok {
			result[i] = value
		}
	}

	destination^ = result
}

config_apply_vec2_array :: proc(
	table: ^Toml_Table,
	key, kind: string,
	id: int,
	destination: ^[]Vec2,
	allocator: mem.Allocator,
) {
	array, ok := toml_get_array(table, key)
	if !ok {
		return
	}

	result := make([]Vec2, len(array), allocator)
	for point_value, i in array {
		point, is_array := point_value.([]Toml_Value)
		if !is_array || len(point) != 2 {
			config_warn_field(kind, id, key, "an array of two-number arrays")
			return
		}
		if x, x_ok := toml_array_get_f32(point, 0); x_ok {
			result[i].x = x
		}
		if y, y_ok := toml_array_get_f32(point, 1); y_ok {
			result[i].y = y
		}
	}
	destination^ = result
}

config_apply_string_array :: proc(
	table: ^Toml_Table,
	key, kind: string,
	id: int,
	destination: ^[]string,
	allocator: mem.Allocator,
) {
	array, ok := toml_get_array(table, key)
	if !ok {
		return
	}

	result := make([]string, len(array), allocator)
	for item, i in array {
		if text, text_ok := item.(string); text_ok {
			result[i] = strings.clone(text, allocator)
		}
	}
	destination^ = result
}

config_apply_weapon_loadout :: proc(
	table: ^Toml_Table,
	id: int,
	destination: ^[]i32,
	allocator: mem.Allocator,
) {
	array, ok := toml_get_array(table, "loadout")
	if !ok || len(array) == 0 {
		return
	}

	result := make([]i32, len(array), allocator)
	for item, i in array {
		name, name_ok := item.(string)
		if !name_ok {
			config_warn_field("class", id, "loadout", "an array of weapon names")
			return
		}

		weapon_id := weapon_config_index(name)
		if weapon_id < 0 {
			config_warn_field("class", id, "loadout", "valid weapon names")
			return
		}

		result[i] = i32(weapon_id)
	}
	destination^ = result
}

config_apply_colors :: proc(table: ^Toml_Table, id: int, destination: ^[6]i32) {
	array, ok := toml_get_array(table, "colors")
	if !ok || len(array) != 6 {
		return
	}

	result: [6]i32
	for item, i in array {
		if color, color_ok := item.(i64); color_ok && color >= i64(min(i32)) && color <= i64(max(i32)) {
			result[i] = i32(color)
		}
	}
	destination^ = result
}

config_apply_weapon :: proc(
	table: ^Toml_Table,
	weapon: ^Weapon,
	id: int,
	allocator: mem.Allocator,
) {
	config_apply_string(table, "name", "weapon", id, &weapon.name, allocator)
	config_apply_string(table, "src", "weapon", id, &weapon.src, allocator)
	config_apply_string(table, "icon", "weapon", id, &weapon.icon, allocator)
	config_apply_string(table, "model", "weapon", id, &weapon.model, allocator)
	config_apply_string(table, "texture", "weapon", id, &weapon.texture, allocator)
	config_apply_string(table, "sound", "weapon", id, &weapon.sound, allocator)

	config_apply_bool(table, "secondary", "weapon", id, &weapon.secondary)
	config_apply_bool(table, "no_spread", "weapon", id, &weapon.no_spread)
	config_apply_bool(table, "akimbo", "weapon", id, &weapon.akimbo)
	config_apply_bool(table, "no_aim", "weapon", id, &weapon.no_aim)
	config_apply_bool(table, "no_auto", "weapon", id, &weapon.no_auto)
	config_apply_bool(table, "no_inspect", "weapon", id, &weapon.no_inspect)
	config_apply_bool(table, "can_throw", "weapon", id, &weapon.can_throw)
	config_apply_bool(table, "melee", "weapon", id, &weapon.melee)
	config_apply_bool(table, "equipment", "weapon", id, &weapon.equipment)
	config_apply_bool(table, "bomb", "weapon", id, &weapon.bomb)
	config_apply_bool(table, "burst", "weapon", id, &weapon.burst)
	config_apply_bool(table, "projectile", "weapon", id, &weapon.projectile)
	config_apply_bool(table, "projectile_disable", "weapon", id, &weapon.projectile_disable)
	config_apply_bool(table, "animate_while_aiming", "weapon", id, &weapon.animate_while_aiming)

	config_apply_u32(table, "burst_count", "weapon", id, &weapon.burst_count)
	config_apply_u32(table, "ammo", "weapon", id, &weapon.ammo)
	config_apply_u32(table, "shots", "weapon", id, &weapon.shots)

	config_apply_f32(table, "burst_rate", "weapon", id, &weapon.burst_rate)
	config_apply_f32(table, "swap_time", "weapon", id, &weapon.swap_time)
	config_apply_f32(table, "reload_time", "weapon", id, &weapon.reload_time)
	config_apply_f32(table, "aim_speed", "weapon", id, &weapon.aim_speed)
	config_apply_f32(table, "speed_mlt", "weapon", id, &weapon.speed_mlt)
	config_apply_f32(table, "jump_mlt", "weapon", id, &weapon.jump_mlt)
	config_apply_f32(table, "damage", "weapon", id, &weapon.damage)
	config_apply_f32(table, "headshot_mlt", "weapon", id, &weapon.headshot_mlt)
	config_apply_f32(table, "pierce", "weapon", id, &weapon.pierce)
	config_apply_f32(table, "range", "weapon", id, &weapon.range)
	config_apply_f32(table, "drop_start", "weapon", id, &weapon.drop_start)
	config_apply_f32(table, "damage_drop", "weapon", id, &weapon.damage_drop)
	config_apply_f32(table, "rate", "weapon", id, &weapon.rate)
	config_apply_f32(table, "spread", "weapon", id, &weapon.spread)
	config_apply_f32(table, "min_spread", "weapon", id, &weapon.min_spread)
	config_apply_f32(table, "recoil", "weapon", id, &weapon.recoil)
	config_apply_f32(table, "recoil_y", "weapon", id, &weapon.recoil_y)
	config_apply_f32(table, "recoil_r", "weapon", id, &weapon.recoil_r)
	config_apply_f32(table, "recover", "weapon", id, &weapon.recover)
	config_apply_f32(table, "recover_y", "weapon", id, &weapon.recover_y)
	config_apply_f32(table, "recover_f", "weapon", id, &weapon.recover_f)
	config_apply_f32(table, "physical_power", "weapon", id, &weapon.physical_power)
	config_apply_f32(table, "physical_range", "weapon", id, &weapon.physical_range)
	config_apply_f32(table, "zoom", "weapon", id, &weapon.zoom)
	config_apply_f32(table, "inaccuracy", "weapon", id, &weapon.inaccuracy)
	config_apply_f32(table, "recoil_y_mlt", "weapon", id, &weapon.recoil_y_mlt)
	config_apply_f32(table, "recoil_z", "weapon", id, &weapon.recoil_z)
	config_apply_f32(table, "recoil_z_mlt", "weapon", id, &weapon.recoil_z_mlt)
	config_apply_f32(table, "rotation", "weapon", id, &weapon.rotation)
	config_apply_f32(table, "z_rotation", "weapon", id, &weapon.z_rotation)
	config_apply_f32(table, "z_rotation_mlt", "weapon", id, &weapon.z_rotation_mlt)
	config_apply_f32(table, "z_lean_mlt", "weapon", id, &weapon.z_lean_mlt)
	config_apply_f32(table, "y_rotation", "weapon", id, &weapon.y_rotation)
	config_apply_f32(table, "rotation_offset", "weapon", id, &weapon.rotation_offset)
	config_apply_f32(table, "rotation_offset_aim", "weapon", id, &weapon.rotation_offset_aim)
	config_apply_f32(table, "jump_y_mlt", "weapon", id, &weapon.jump_y_mlt)
	config_apply_f32(table, "land_bob", "weapon", id, &weapon.land_bob)
	config_apply_f32(table, "aim_recoil_mlt", "weapon", id, &weapon.aim_recoil_mlt)
	config_apply_f32(table, "lean_mlt", "weapon", id, &weapon.lean_mlt)
	config_apply_f32(table, "inspect_rotation", "weapon", id, &weapon.inspect_rotation)
	config_apply_f32(table, "inspect_mlt", "weapon", id, &weapon.inspect_mlt)
	config_apply_f32(table, "crouch_lean", "weapon", id, &weapon.crouch_lean)
	config_apply_f32(table, "crouch_rotation", "weapon", id, &weapon.crouch_rotation)
	config_apply_f32(table, "crouch_drop", "weapon", id, &weapon.crouch_drop)
	config_apply_f32(table, "scale", "weapon", id, &weapon.scale)
	config_apply_f32(table, "hold_width", "weapon", id, &weapon.hold_width)
	config_apply_f32(table, "hold_distance_offset", "weapon", id, &weapon.hold_distance_offset)

	config_apply_vec3(table, "origin", "weapon", id, &weapon.origin)
	config_apply_vec3(table, "offset", "weapon", id, &weapon.offset)
	config_apply_vec3(table, "left_hold", "weapon", id, &weapon.left_hold)
	config_apply_vec3(table, "right_hold", "weapon", id, &weapon.right_hold)
	config_apply_vec2_array(table, "custom_spread", "weapon", id, &weapon.custom_spread, allocator)
}

config_apply_class :: proc(
	table: ^Toml_Table,
	class: ^Class_Config,
	id: int,
	allocator: mem.Allocator,
) {
	config_apply_string(table, "name", "class", id, &class.name, allocator)
	config_apply_i32(table, "icon_index", "class", id, &class.icon_index)
	config_apply_string_array(table, "texts", "class", id, &class.texts, allocator)
	config_apply_weapon_loadout(table, id, &class.loadout, allocator)
	config_apply_bool(table, "secondary", "class", id, &class.secondary)
	config_apply_bool(table, "wall_jump", "class", id, &class.wall_jump)
	config_apply_colors(table, id, &class.colors)
	config_apply_i32(table, "health", "class", id, &class.health)
	config_apply_i32(table, "health_segments", "class", id, &class.health_segments)
	config_apply_f32(table, "regen", "class", id, &class.regen)
	config_apply_f32(table, "speed", "class", id, &class.speed)
}
