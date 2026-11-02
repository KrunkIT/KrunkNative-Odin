package shared

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

// Lighting_Config contains the environment values exported by the current
// Krunker renderer.  Colors are normalized RGB values (0..1), regardless of
// whether the export encoded them as a packed integer or a CSS hex string.
// The renderer can use this as a per-map scene description without depending
// on the large raw export object.
Lighting_Config :: struct {
	ambient_color:                Vec3,
	ambient_intensity:            f32,
	fog_color:                    Vec3,
	fog_distance:                 f32,
	light_color:                  Vec3,
	light_distance:               f32,
	light_intensity:              f32,
	sky_color:                    Vec3,
	sky_dome:                     bool,
	sky_dome_colors:              [3]Vec3,
	sky_dome_emissive_texture:    i32,
	sky_dome_texture:             bool,
	sky_dome_texture_asset:       i32,
	sun_angle_x:                  f32,
	sun_angle_y:                  f32,
}

DEFAULT_LIGHTING_CONFIG :: Lighting_Config {
	// Defaults mirror addEnvironmentZone in game.deob.js.
	ambient_color             = Vec3{151.0 / 255.0, 160.0 / 255.0, 168.0 / 255.0},
	ambient_intensity         = 1.0,
	fog_color                 = Vec3{141.0 / 255.0, 154.0 / 255.0, 160.0 / 255.0},
	fog_distance              = 2000.0,
	light_color               = Vec3{242.0 / 255.0, 248.0 / 255.0, 252.0 / 255.0},
	// Browser's default directional-light distance (used when old maps omit
	// lightD). Direction is normalized by the shader, so zero is invalid.
	light_distance            = 450.0,
	light_intensity           = 1.3,
	sky_color                 = Vec3{220.0 / 255.0, 232.0 / 255.0, 237.0 / 255.0},
	sky_dome                  = false,
	sky_dome_colors           = [3]Vec3{Vec3{0.4, 0.6, 0.8}, Vec3{0.7, 0.8, 0.9}, Vec3{1, 1, 1}},
	sky_dome_emissive_texture = 0,
	sky_dome_texture          = false,
	sky_dome_texture_asset    = 0,
	sun_angle_x               = 90.0,
	sun_angle_y               = 54.0,
}

lighting_json_f32 :: proc(value: json.Value, fallback: f32) -> f32 {
	#partial switch v in value {
	case json.Float:
		return f32(v)
	case json.Integer:
		return f32(v)
	}
	return fallback
}

lighting_json_bool :: proc(value: json.Value, fallback: bool) -> bool {
	#partial switch v in value {
	case json.Boolean:
		return bool(v)
	}
	return fallback
}

lighting_json_i32 :: proc(value: json.Value, fallback: i32) -> i32 {
	#partial switch v in value {
	case json.Integer:
		return i32(v)
	case json.Float:
		return i32(v)
	}
	return fallback
}

lighting_json_color :: proc(value: json.Value, fallback: Vec3) -> Vec3 {
	#partial switch v in value {
	case json.Integer:
		packed := i32(v)
		return Vec3{f32(packed >> 16 & 0xff) / 255.0, f32(packed >> 8 & 0xff) / 255.0, f32(packed & 0xff) / 255.0}
	case json.Float:
		packed := i32(v)
		return Vec3{f32(packed >> 16 & 0xff) / 255.0, f32(packed >> 8 & 0xff) / 255.0, f32(packed & 0xff) / 255.0}
	case json.String:
		parsed := Vec4{}
		if parse_hex_color(string(v), &parsed) {
			return Vec3{parsed.x, parsed.y, parsed.z}
		}
	}
	return fallback
}

// lighting_parse_json accepts either a complete krunker-sky-export document
// or the settings object itself.  It intentionally reads only stable fields;
// map geometry and mode overrides remain owned by the map loader.
lighting_parse_json :: proc(value: json.Value) -> (config: Lighting_Config, ok: bool) {
	config = DEFAULT_LIGHTING_CONFIG
	root, is_object := value.(json.Object)
	if !is_object do return config, false

	settings := root
	if current, found := root["current"]; found {
		if current_object, current_ok := current.(json.Object); current_ok {
			if current_settings, settings_ok := current_object["settings"]; settings_ok {
				if settings_object, object_ok := current_settings.(json.Object); object_ok {
					settings = settings_object
				}
			}
		}
	} else if nested, found := root["settings"]; found {
		if nested_object, nested_ok := nested.(json.Object); nested_ok { settings = nested_object }
	}

	if raw, found := settings["ambient"]; found { config.ambient_color = lighting_json_color(raw, config.ambient_color) }
	if raw, found := settings["ambientI"]; found { config.ambient_intensity = lighting_json_f32(raw, config.ambient_intensity) }
	if raw, found := settings["fog"]; found { config.fog_color = lighting_json_color(raw, config.fog_color) }
	if raw, found := settings["fogD"]; found { config.fog_distance = lighting_json_f32(raw, config.fog_distance) }
	if raw, found := settings["light"]; found { config.light_color = lighting_json_color(raw, config.light_color) }
	if raw, found := settings["lightD"]; found { config.light_distance = lighting_json_f32(raw, config.light_distance) }
	if raw, found := settings["lightI"]; found { config.light_intensity = lighting_json_f32(raw, config.light_intensity) }
	if raw, found := settings["sky"]; found { config.sky_color = lighting_json_color(raw, config.sky_color) }
	if raw, found := settings["skyDome"]; found { config.sky_dome = lighting_json_bool(raw, config.sky_dome) }
	if raw, found := settings["skyDomeCol0"]; found { config.sky_dome_colors[0] = lighting_json_color(raw, config.sky_dome_colors[0]) }
	if raw, found := settings["skyDomeCol1"]; found { config.sky_dome_colors[1] = lighting_json_color(raw, config.sky_dome_colors[1]) }
	if raw, found := settings["skyDomeCol2"]; found { config.sky_dome_colors[2] = lighting_json_color(raw, config.sky_dome_colors[2]) }
	if raw, found := settings["skyDomeEmisTex"]; found { config.sky_dome_emissive_texture = lighting_json_i32(raw, config.sky_dome_emissive_texture) }
	if raw, found := settings["skyDomeTex"]; found { config.sky_dome_texture = lighting_json_bool(raw, config.sky_dome_texture) }
	if raw, found := settings["skyDomeTexA"]; found { config.sky_dome_texture_asset = lighting_json_i32(raw, config.sky_dome_texture_asset) }
	if raw, found := settings["sunAngY"]; found { config.sun_angle_y = lighting_json_f32(raw, config.sun_angle_y) }
	if raw, found := settings["sunAngX"]; found { config.sun_angle_x = lighting_json_f32(raw, config.sun_angle_x) }

	return config, true
}

lighting_load_from_file :: proc(filename: string) -> (config: Lighting_Config, ok: bool) {
	data, err := os.read_entire_file_from_path(filename, context.allocator)
	if err != nil {
		fmt.eprintf("Failed to read lighting config %s: %v\n", filename, err)
		return DEFAULT_LIGHTING_CONFIG, false
	}
	defer delete(data)
	value, parse_err := json.parse_string(string(data), parse_integers = true)
	if parse_err != .None {
		fmt.eprintf("Failed to parse lighting config %s: %v\n", filename, parse_err)
		return DEFAULT_LIGHTING_CONFIG, false
	}
	defer json.destroy_value(value)
	return lighting_parse_json(value)
}

// The exported sky captures are intentionally kept outside assets/maps. When
// present, these current captures override the environment embedded in older
// map JSON files. Missing captures remain optional so packaged clients can
// still use the map's embedded values.
lighting_map_override_path :: proc(filename: string) -> string {
	lower := strings.to_lower(filename)
	defer delete(lower)
	if strings.contains(lower, "sandstorm") { return "krunker-configs/Sandstorm-Config-2026-11-01T18-19-09-832Z.json" }
	if strings.contains(lower, "undergrowth") { return "krunker-configs/Undergrowth-Config-2026-11-01T18-19-43-132Z.json" }
	if strings.contains(lower, "subzero") { return "krunker-configs/Subzero-Config-2026-11-01T18-18-24-715Z.json" }
	if strings.contains(lower, "industry") { return "krunker-configs/Industry-Config-2026-11-01T18-21-03-353Z.json" }
	if strings.contains(lower, "bureau") { return "krunker-configs/Bureau-Config-2026-11-01T18-21-38-340Z.json" }
	if strings.contains(lower, "burg") { return "krunker-configs/Burg-Config-2026-11-01T18-17-33-116Z.json" }
	if strings.contains(lower, "site") { return "krunker-configs/Site-Config-2026-11-01T18-20-13-768Z.json" }
	return ""
}
