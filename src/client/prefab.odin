package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import shared "../shared"

Prefab_Model :: struct {
	filename:    string,
	scale:       f32,
	transparent: bool,
	frames:      int,
	frame_time:  f32,
}

// Ordering matches the legacy Prefab enum values, followed by the current
// browser's raw prefab IDs (60..98) that are not represented by the old enum.
prefab_models := [?]Prefab_Model{
	{},                              // cube (software-generated)
	{"crate_0", 6.0, false, 0, 0},
	{"barrel_0", 4.0, false, 0, 0},
	{},                              // ladder (software-generated)
	{},                              // plane (software-generated)
	{},                              // spawnpoint
	{},                              // camera position
	{"vehicle_0", 20.0, false, 0, 0},
	{"stack_0", 6.0, false, 0, 0},
	{},                              // ramp (software-generated)
	{},                              // score zone
	{},                              // billboard (software-generated)
	{},                              // death zone
	{},                              // particles
	{},                              // objective
	{"tree_0", 10.0, false, 0, 0},
	{"cone_0", 4.0, false, 0, 0},
	{"container_0", 7.0, false, 0, 0},
	{"grass_0", 32.0, true, 4, 0.180},
	{"containerr_0", 7.0, false, 0, 0},
	{"acidbarrel_0", 4.0, false, 0, 0},
	{"door_0", 5.0, false, 0, 0},
	{"window_0", 6.0, true, 0, 0},
	{},                              // flag
	{},                              // gate
	{},                              // check point
	{},                              // weapon pickup (software-generated)
	{},                              // teleporter
	{"teddy_0", 6.0, false, 0, 0},
	{},                              // trigger
	{},                              // sign (software-generated)
	{},                              // deposit box
	{},                              // light cone
	{},                              // spectate cam
	{},                              // sphere (software-generated)
	{},                              // placeholder
	{"cardb_0", 5.0, false, 0, 0},
	{"pallet_0", 6.0, false, 0, 0},
	{},                              // liquid
	{},                              // sound emitter
	{},                              // event
	{},                              // terminal
	{},                              // premium zone
	{},                              // verified zone
	{},                              // custom asset
	{},                              // bomb site
	{},                              // boost pad (software-generated)
	{},                              // team zone
	{},                              // cylinder (software-generated)
	{"police_0", 4.0, false, 0, 0},
	{"cage_0", 6.0, false, 0, 0},
	{"ebarrel_0", 4.0, false, 0, 0},
	{},                              // showcase
	{},                              // point light
	{"ghost_0", 4.0, false, 0, 0},
	{"ghost_0", 4.0, true, 0, 0},   // AI spawner (live prefab 55)
	{"pumpkin_0", 4.0, false, 0, 0},
	{},                              // rune (software-generated)
	{"skeleton_0", 4.0, false, 0, 0},
	{"knight_0", 4.0, false, 0, 0},
	{"gift_0", 2.0, false, 0, 0},
	{"christmastree_0", 2.0, false, 0, 0},
	{"cane_0", 2.0, false, 0, 0},
	{},                              // light bar
	{},                              // path node
	{},                              // directional light
	{},                              // rect area light
	{},                              // spot light
	{},                              // prize wheel
	{},                              // KR zone
	{},                              // no-PvP zone
	{},                              // PvP zone
	{},                              // leaderboard
	{"tiles_0", 10.0, false, 0, 0},
	{"clouds_0", 3.0, true, 0, 0},
	{},                              // partner zone
	{},                              // sprite
	{},                              // domination zone
	{},                              // rope ladder
	{},                              // environment zone
	{},                              // KPD zone
	{"dumpster_0", 4.0, false, 0, 0},
	{},                              // server node
	{"lamp_0", 1.0, false, 0, 0},
	{"water_tower_0", 10.0, false, 0, 0},
	{"ac_unit_0", 5.0, false, 0, 0},
	{"sheet_metal_0", 0.5, false, 0, 0},
	{"antenna_0", 10.0, false, 0, 0},
	{"satellite_dish_0", 5.0, false, 0, 0},
	{},                              // spray
	{"weaponbox_0", 5.0, false, 0, 0},
	{"weaponbox_0", 5.0, false, 0, 0},
	{"perkmachine_0", 5.0, false, 0, 0},
	{},                              // AI redirection
	{"krummachine_0", 7.0, false, 0, 0},
	{},                              // bot spawner
	{},                              // map anchor
	{"crate_0", 5.0, false, 0, 0},
	{},                              // entity
}

prefab_textures := [?]string{
	"wall",
	"dirt",
	"floor",
	"grid",
	"grey",
	// The DEFAULT slot intentionally has no texture in the live registry.
	"default",
	"roof",
	"flag",
	"grass",
	"check",
	"lines",
	"brick",
	"link",
	"liquid",
	"grain",
	"fabric",
	"tile",
	"metal",
	"sand",
	"snow",
}

prefab_init :: proc(object: ^shared.Object, colors: []shared.Vec4, raw_obj: json.Value) -> ^Mesh {
	obj_obj, is_obj := raw_obj.(json.Object)
	if !is_obj {
		return nil
	}

	prefab_id := int(object.prefab)

	// `aid` is also used by newer AI/spawner prefabs whose numeric IDs are
	// outside the legacy native prefab table. Resolve the asset before applying
	// the table bounds check so a supported static asset can still be rendered.
	prefab_model := Prefab_Model{}
	if prefab_id >= 0 && prefab_id < len(prefab_models) {
		prefab_model = prefab_models[prefab_id]
	}
	alpha_test: f32
	custom_asset_found := false
	custom_unlit := false

	if aid, is_string := obj_obj["aid"].(json.String); is_string {
		asset, supported := shared.map_custom_asset(string(aid))
		if supported {
			prefab_model = Prefab_Model{filename = asset.filename, scale = 1.0}
			alpha_test = asset.alpha_test
			custom_asset_found = true
			custom_unlit = asset.emissive
		}
	}
	if prefab_id == int(shared.Prefab.CUSTOM_ASSET) && !custom_asset_found {
		return nil
	}
	if prefab_id < 0 || prefab_id >= len(prefab_models) {
		if !custom_asset_found {
			return nil
		}
	}

	raw_visibility, has_visibility := obj_obj["v"]
	raw_rotation, has_rotation := obj_obj["r"]
	raw_color, has_color := obj_obj["c"]
	raw_color_idx, has_color_idx := obj_obj["ci"]
	raw_emissive, has_emissive := obj_obj["e"]
	raw_emissive_idx, has_emissive_idx := obj_obj["ei"]
	raw_opacity, has_opacity := obj_obj["o"]
	raw_model_size, has_model_size := obj_obj["ms"]

	opacity := 1.0 if !has_opacity else get_json_f32(raw_opacity)

	color := shared.Vec4{1.0, 1.0, 1.0, 1.0}
	emissive := shared.Vec4{1.0, 1.0, 1.0, 1.0}

	if has_color {
		if hex, is_str := raw_color.(json.String); is_str {
			shared.parse_hex_color(hex, &color)
		}
	} else if has_color_idx {
		idx := int(get_json_f32(raw_color_idx))
		if idx >= 0 && idx < len(colors) {
			color = colors[idx]
		}
	}

	if has_emissive {
		if hex, is_str := raw_emissive.(json.String); is_str {
			shared.parse_hex_color(hex, &emissive)
		}
	} else if has_emissive_idx {
		idx := int(get_json_f32(raw_emissive_idx))
		if idx >= 0 && idx < len(colors) {
			emissive = colors[idx]
		}
	}

	visible := !(has_visibility && json_is_number(raw_visibility) && get_json_f32(raw_visibility) == 1.0)
	rotation := shared.Vec3{0, 0, 0}

	if has_rotation {
		if rot_arr, is_arr := raw_rotation.(json.Array); is_arr && len(rot_arr) >= 3 {
			rotation.x = get_json_f32(rot_arr[0])
			rotation.y = get_json_f32(rot_arr[1])
			rotation.z = get_json_f32(rot_arr[2])

			if rotation.x != rotation.x {
				rotation.x = 0.0
			}
			if rotation.y != rotation.y {
				rotation.y = 0.0
			}
			if rotation.z != rotation.z {
				rotation.z = 0.0
			}
		}
	}

	if prefab_model.frames > 0 {
		if object.tex_anim == nil {
			object.tex_anim = new(shared.Texture_Animation)
		}

		if object.tex_anim != nil {
			object.tex_anim.frames = i32(prefab_model.frames)
			object.tex_anim.frame_time = prefab_model.frame_time
		}
	}

	// models
	if len(prefab_model.filename) > 0 {
		model_name := prefab_model.filename
		geometry_variant := model_geometry_variant(prefab_id, int(object.texture_variant))
		if !custom_asset_found && geometry_variant > 0 {
			model_name = fmt.tprintf("%s_%d", model_name, geometry_variant)
		}
		model_path := shared.concat(shared.assets_path(), fmt.tprintf("models/%s.obj", model_name))
		model_texture_name := prefab_model.filename
		// Hosted custom assets have a single model.png. `tv` variants belong to
		// the built-in prefab registry and must not invent custom/<id>_<tv>.png.
		if !custom_asset_found && object.texture_variant > 0 {
			model_texture_name = fmt.tprintf("%s_%d", model_texture_name, object.texture_variant)
		}
		texture_path := shared.concat(shared.assets_path(), fmt.tprintf("textures/%s.png", model_texture_name))
		base_texture_path := shared.concat(shared.assets_path(), fmt.tprintf("textures/%s.png", prefab_model.filename))

		texture_id := load_texture_with_fallback(texture_path, base_texture_path)
		geometry := load_obj_model(model_path, true)

		delete(model_path)
		delete(texture_path)
		delete(base_texture_path)

		if geometry == nil {
			texture_release(texture_id)
			return nil
		}

		material := basic_material_init()
		mesh := mesh_init(geometry, &material.base)

		mesh.visible = visible
		mesh.transform.position = object.position
		mesh.transform.rotation = rotation

		scale := prefab_model.scale if !has_model_size else get_json_f32(raw_model_size)
		mesh.transform.scale = shared.Vec3{scale, scale, scale}

		material.base.transparent = prefab_model.transparent || opacity != 1.0
		material.alpha_test = alpha_test
		material.texture = texture_id
		material.color = color
		material.color.w = opacity
		material.emissive = emissive
		material.unlit = custom_unlit

		return mesh
	}

	// procedural geometries
	tex_id := 0
	if t_val, has_t := obj_obj["t"]; has_t && json_is_number(t_val) {
		tex_id = int(get_json_f32(t_val))
	}

	texture_path: string

	if prefab_id == int(shared.Prefab.BILLBOARD) {
		billboard_id := 0
		if bb, has_bb := obj_obj["bb"]; has_bb && json_is_number(bb) {
			billboard_id = int(get_json_f32(bb))
		}

		if billboard_id == 0 {
			billboard_id = 1
		}

		texture_path = shared.concat(shared.assets_path(), fmt.tprintf("textures/pubs/b_%d.png", billboard_id))
	} else {
		name := prefab_textures[tex_id] if tex_id >= 0 && tex_id < len(prefab_textures) else "default"
		if name == "default" {
			// The live DEFAULT material is untextured; the shader's neutral white
			// fallback is intentional here.
			texture_path = ""
		} else {
			variant := 0
			variant = max(0, int(object.texture_variant))
			base := name
			base_suffix := "_0"
			if tex_id == 8 {
				// Grass is registered as grass_1 in the browser texture table.
				base_suffix = "_1"
			}
			texture_file := fmt.tprintf("%s%s", base, base_suffix)
			if variant > 0 {
				texture_file = fmt.tprintf("%s_%d", texture_file, variant)
			}
			texture_path = shared.concat(shared.assets_path(), fmt.tprintf("textures/%s.png", texture_file))
		}
	}

	texture_id: u32 = 0
	if len(texture_path) > 0 {
		base_texture_path := ""
		if tex_id >= 0 && tex_id < len(prefab_textures) && prefab_textures[tex_id] != "default" {
			name := prefab_textures[tex_id]
			base_suffix := tex_id == 8 ? "_1" : "_0"
			base_texture_path = shared.concat(shared.assets_path(), fmt.tprintf("textures/%s%s.png", name, base_suffix))
		}
		texture_id = load_texture_with_fallback(texture_path, base_texture_path)
		delete(texture_path)
		if len(base_texture_path) > 0 {
			delete(base_texture_path)
		}
	}

	if ts, has_ts := obj_obj["ts"]; has_ts && json_is_number(ts) {
		if object.tex_anim == nil {
			object.tex_anim = new(shared.Texture_Animation)
		}

		if object.tex_anim != nil {
			// The browser's render delta is milliseconds; native animation time is
			// seconds, so preserve the equivalent per-second UV velocity.
			object.tex_anim.move = get_json_f32(ts) / 10.0

			td, has_td := obj_obj["td"]
			object.tex_anim.move_direction = has_td && json_is_number(td) ? i32(get_json_f32(td)) % 2 : 0
		}
	}

	if prefab_id == int(shared.Prefab.CUBE) || prefab_id == int(shared.Prefab.PLANE) || prefab_id == int(shared.Prefab.BILLBOARD) {
	geometry: ^Geometry

		if prefab_id == int(shared.Prefab.CUBE) {
			geometry = create_cube_geo()
		} else {
			geometry = create_plane_geo()
		}

		if geometry == nil {
			return nil
		}

		material := basic_material_init()
		mesh := mesh_init(geometry, &material.base)

		mesh.visible = visible
		mesh.transform.position = object.position
		mesh.transform.rotation = rotation
		mesh.transform.scale = object.scale

		material.texture = texture_id
		material.color = color
		material.color.w = opacity
		material.emissive = emissive
		material.unlit = custom_unlit
		// Map cubes using the grass and chain-link textures carry alpha masks.
		// Keep their zero-alpha texels out of the opaque pass so the fence shows
		// the world behind it instead of rendering its transparent pixels black.
		if tex_id == 8 || tex_id == 12 {
			material.base.transparent = true
			material.alpha_test = 0.01
		}
		apply_object_material_properties(material, object, obj_obj)

		material.use_face_tex_scaling = prefab_id != int(shared.Prefab.BILLBOARD)
		material.face_scale = object.scale

		if prefab_id != int(shared.Prefab.CUBE) {
			mesh.transform.scale.y = 0.01

			material.face_scale.x = object.scale.x
			material.face_scale.y = object.scale.z
		}

		return mesh
	}

	if prefab_id == int(shared.Prefab.RAMP) {
		geometry := create_ramp_geo()
		if geometry == nil {
			return nil
		}

		material := basic_material_init()
		mesh := mesh_init(geometry, &material.base)

		mesh.visible = visible
		mesh.transform.position = object.position
		mesh.transform.rotation.y = -math.PI / 2.0 * (1.0 + f32(object.direction))
		mesh.transform.scale.y = object.scale.y

		if object.direction % 2 == 1 {
			mesh.transform.scale.x = object.scale.x
			mesh.transform.scale.z = object.scale.z
		} else {
			mesh.transform.scale.x = object.scale.z
			mesh.transform.scale.z = object.scale.x
		}

		material.texture = texture_id
		material.color = color
		material.emissive = emissive
		apply_object_material_properties(material, object, obj_obj)

		material.is_ramp = true
		material.use_face_tex_scaling = true
		material.face_scale = mesh.transform.scale

		return mesh
	}

	if prefab_id == int(shared.Prefab.LADDER) {
		geometry := create_ladder_geo(object.scale.y)
		if geometry == nil {
			return nil
		}

		material := basic_material_init()
		mesh := mesh_init(geometry, &material.base)

		mesh.visible = visible
		mesh.transform.position = object.position
		mesh.transform.rotation.y = math.PI * 0.5 * f32(i32(object.direction) - 1)

		material.texture = texture_id
		material.color = color
		material.emissive = emissive
		apply_object_material_properties(material, object, obj_obj)

		material.is_ladder = true
		material.use_face_tex_scaling = true

		material.face_scale = shared.Vec3{
			shared.GAME_CONSTANTS.ladder_width * 2.0,
			mesh.transform.scale.y,
			shared.GAME_CONSTANTS.ladder_scale * 2.0,
		}

		return mesh
	}

	if prefab_id == int(shared.Prefab.SCORE_ZONE) || prefab_id == int(shared.Prefab.OBJECTIVE) {
		texture_release(texture_id)
		geometry := create_plane_geo()
		if geometry == nil {
			return nil
		}

		material := basic_material_init()
		mesh := mesh_init(geometry, &material.base)
		mesh.transform.position = object.position
		mesh.transform.position.y += 0.08
		mesh.transform.scale = shared.Vec3{object.scale.x, 0.01, object.scale.z}
		material.base.transparent = true
		material.color = shared.Vec4{0.4, 0.45, 0.5, 0.16}
		material.emissive = shared.Vec4{0.05, 0.05, 0.05, 1.0}
		material.face_scale = shared.Vec3{object.scale.x, object.scale.z, 1.0}
		return mesh
	}

	// Non-renderable gameplay markers and unsupported prefabs should not become
	// visible wireframe collision boxes in production rendering.
	texture_release(texture_id)
	return nil
}

// A live prefab variant can change only its texture, or it can replace the
// complete OBJ. The browser marks the latter with `diffM`; these are the
// variants for which the native model path also carries the variant suffix.
model_geometry_variant :: proc(prefab_id, texture_variant: int) -> int {
	if texture_variant <= 0 do return 0
	switch prefab_id {
	case int(shared.Prefab.CRATE):
		return texture_variant >= 2 && texture_variant <= 4 ? texture_variant : 0
	case int(shared.Prefab.BARREL):
		return texture_variant <= 5 ? texture_variant : 0
	case int(shared.Prefab.VEHICLE):
		return texture_variant >= 2 && texture_variant <= 3 ? texture_variant : 0
	case int(shared.Prefab.TREE):
		return texture_variant <= 8 ? texture_variant : 0
	case int(shared.Prefab.CONE):
		return texture_variant == 1 ? 1 : 0
	case int(shared.Prefab.ACID_BARREL):
		return texture_variant == 1 ? 1 : 0
	case int(shared.Prefab.DOOR):
		return texture_variant <= 3 ? texture_variant : 0
	case int(shared.Prefab.WINDOW):
		return texture_variant <= 6 ? texture_variant : 0
	case int(shared.Prefab.E_BARREL):
		return texture_variant <= 2 ? texture_variant : 0
	case 83: // LAMP
		return texture_variant <= 2 ? texture_variant : 0
	case 84: // WATER_TOWER
		return texture_variant == 1 ? 1 : 0
	case 87: // ANTENNA
		return texture_variant <= 3 ? texture_variant : 0
	}
	return 0
}

// Current maps can reference a texture variant introduced after the local
// asset pack was built. The browser falls back to the texture's base source
// when a variant is unavailable; keep that behavior instead of binding the
// white blank texture and making an entire map surface disappear.
load_texture_with_fallback :: proc(primary, fallback: string) -> u32 {
	texture_id := load_texture(primary)
	if texture_id == 0 && len(fallback) > 0 && primary != fallback {
		fmt.eprintf("[assets] missing texture %s; falling back to %s\n", primary, fallback)
		texture_id = load_texture(fallback)
	}
	return texture_id
}

get_json_f32 :: proc(val: json.Value) -> f32 {
	#partial switch v in val {
	case json.Float:
		return f32(v)
	case json.Integer:
		return f32(v)
	}

	return 0.0
}

// Apply map-authored texture metadata after the base material has been built.
// These fields are present on current exports and are responsible for the
// rotated/offset wall and trim textures in maps such as Sandstorm v3.
apply_object_material_properties :: proc(material: ^Basic_Material, object: ^shared.Object, raw_obj: json.Object) {
	if object.prefab == .CUBE {
		material.face_mask = object.face_mask
	}

	if tox, ok := raw_obj["tox"]; ok && json_is_number(tox) {
		material.texture_offset.x = get_json_f32(tox)
	}
	if toy, ok := raw_obj["toy"]; ok && json_is_number(toy) {
		material.texture_offset.y = get_json_f32(toy)
	}
	if tro, ok := raw_obj["tro"]; ok && json_is_number(tro) {
		material.texture_rotation = get_json_f32(tro) * math.PI / 180.0
	}
	if tsm, ok := raw_obj["tsm"]; ok && json_is_number(tsm) {
		scale := get_json_f32(tsm)
		if scale > 0 {
			material.texture_scale = scale
		}
	}
	material.base_texture_offset = material.texture_offset
}

json_is_number :: proc(val: json.Value) -> bool {
	#partial switch v in val {
	case json.Float, json.Integer:
		return true
	}

	return false
}

client_animate_object_texture :: proc(object: ^shared.Object, now: f32) {
	if object.mesh == nil || object.tex_anim == nil {
		return
	}

	mesh := cast(^Mesh)object.mesh
	tex_anim := object.tex_anim

	if mesh.material.vtable != &basic_material_vtable {
		return
	}

	material := cast(^Basic_Material)mesh.material
	material.texture_offset = material.base_texture_offset

	if tex_anim.frames != 0 {
		frame := int(math.mod(now, f32(tex_anim.frames) * tex_anim.frame_time) / tex_anim.frame_time)

		material.texture_repeat.x = 1.0 / f32(tex_anim.frames)
		material.texture_offset.x += f32(frame) / f32(tex_anim.frames)
	}

	if tex_anim.move != 0 {
		progress := math.mod(now * tex_anim.move, 1.0)

		if tex_anim.move_direction != 0 {
			material.texture_offset.y += progress
		} else {
			material.texture_offset.x += progress
		}
	}
}
