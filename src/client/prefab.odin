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

// Ordering matches the Prefab enum values in the C port.
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
	{},                              // bot
	{"pumpkin_0", 4.0, false, 0, 0},
	{},                              // rune (software-generated)
	{"skeleton_0", 4.0, false, 0, 0},
	{"knight_0", 4.0, false, 0, 0},
}

prefab_textures := [?]string{
	"wall",
	"dirt",
	"floor",
	"grid",
	"grey",
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
}

custom_asset_tree_ids := [?]string{
	"2412a",
}

prefab_init :: proc(object: ^shared.Object, colors: []shared.Vec4, raw_obj: json.Value) -> ^Mesh {
	obj_obj, is_obj := raw_obj.(json.Object)
	if !is_obj {
		return nil
	}

	prefab_id := int(object.prefab)

	if prefab_id < 0 || prefab_id >= len(prefab_models) {
		return nil
	}

	prefab_model := prefab_models[prefab_id]

	if prefab_id == int(shared.Prefab.CUSTOM_ASSET) {
		if aid_val, has_aid := obj_obj["aid"]; has_aid {
			if aid_str, is_str := aid_val.(json.String); is_str {
				for tree_id in custom_asset_tree_ids {
					if aid_str == tree_id {
						prefab_model = prefab_models[int(shared.Prefab.TREE)]
						break
					}
				}
			}
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
		model_path := shared.concat(shared.assets_path(), fmt.tprintf("models/%s.obj", prefab_model.filename))
		texture_path := shared.concat(shared.assets_path(), fmt.tprintf("textures/%s.png", prefab_model.filename))

		texture_id := load_texture(texture_path)
		geometry := load_obj_model(model_path, true)

		delete(model_path)
		delete(texture_path)

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
		material.texture = texture_id
		material.color = color
		material.color.w = opacity
		material.emissive = emissive

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
		texture_path = shared.concat(shared.assets_path(), fmt.tprintf("textures/%s_%d.png", name, tex_id == 8 ? 1 : 0))
	}

	texture_id := load_texture(texture_path)
	delete(texture_path)

	if ts, has_ts := obj_obj["ts"]; has_ts && json_is_number(ts) {
		if object.tex_anim == nil {
			object.tex_anim = new(shared.Texture_Animation)
		}

		if object.tex_anim != nil {
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

get_json_f32 :: proc(val: json.Value) -> f32 {
	#partial switch v in val {
	case json.Float:
		return f32(v)
	case json.Integer:
		return f32(v)
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

	if tex_anim.frames != 0 {
		frame := int(math.mod(now, f32(tex_anim.frames) * tex_anim.frame_time) / tex_anim.frame_time)

		material.texture_repeat.x = 1.0 / f32(tex_anim.frames)
		material.texture_offset.x = f32(frame)
	}

	if tex_anim.move != 0 {
		period := 1.0 / tex_anim.move
		progress := math.mod(now, period) / period

		if tex_anim.move_direction != 0 {
			material.texture_offset.y = progress
		} else {
			material.texture_offset.x = progress
		}
	}
}
