package main

import "core:fmt"
import "core:math"
import shared "../shared"

Color_Cube_Segment :: struct {
	color:  i32,
	height: f32,
	scale:  f32,
}

generate_color_cube :: proc(width, height, length: f32, segments: []Color_Cube_Segment) -> ^Color_Cube {
	color_cube := new(Color_Cube)
	color_cube.mesh_count = i32(len(segments))

	color_cube.transform.scale = shared.Vec3{width, height, length}

	offset: f32 = 0.5

	for segment in segments {
		geo := create_cube_geo()
		material := basic_material_init()

		mesh := mesh_init(geo, &material.base)

		material.color = shared.hex_to_vec(segment.color)

		mesh.transform.scale.x = segment.scale
		mesh.transform.scale.z = segment.scale
		mesh.transform.scale.y = segment.height

		mesh.transform.position.y = offset - segment.height
		mesh.transform.parent = &color_cube.transform

		offset -= segment.height
		append(&color_cube.meshes, mesh)
	}

	return color_cube
}

generate_arm :: proc(x, y: f32, weapon: ^shared.Weapon, is_left, third_person, left_handed: bool, shirt_color, sleeve_color, skin_color: i32) -> ^Player_Arm_Mesh {
	arm := new(Player_Arm_Mesh)

	left_handed_mlt: f32 = left_handed ? -1.0 : 1.0

	hold := shared.Vec3{
		(is_left ? weapon.left_hold.x : weapon.right_hold.x) * left_handed_mlt,
		is_left ? weapon.left_hold.y : weapon.right_hold.y,
		is_left ? weapon.left_hold.z : weapon.right_hold.z,
	}

	arm_scale := shared.GAME_CONSTANTS.arm_scale * (third_person ? 1.0 : 0.68)
	arm_length := min(
		shared.GAME_CONSTANTS.upper_arm_length + shared.GAME_CONSTANTS.lower_arm_length - 0.01,
		math.sqrt(
			math.pow((weapon.offset.x * left_handed_mlt - hold.x) * (is_left && weapon.akimbo ? -1.0 : 1.0) - x, 2.0) +
			math.pow(weapon.offset.y + hold.y - y, 2.0) +
			math.pow(weapon.offset.z - hold.z, 2.0),
		),
	)

	arm_angles := shared.angles_from_sides(arm_length, shared.GAME_CONSTANTS.upper_arm_length, shared.GAME_CONSTANTS.lower_arm_length)

	if third_person {
		upper_material := basic_material_init()
		joint_material := basic_material_init()

		upper_material.color = shared.hex_to_vec(shirt_color)
		joint_material.color = shared.hex_to_vec(shirt_color)

		arm.upper = mesh_init(create_cube_geo(), &upper_material.base)
		arm.joint = mesh_init(create_cube_geo(), &joint_material.base)

		arm.upper.transform.scale.x = arm_scale
		arm.upper.transform.scale.z = arm_scale
		arm.upper.transform.scale.y = shared.GAME_CONSTANTS.upper_arm_length

		arm.upper.transform.rotation.x = -math.PI * 0.5
		arm.upper.transform.parent = &arm.anchor

		joint_length := math.sqrt(2.0 * arm_scale * 0.5 * arm_scale * 0.5 - 2.0 * arm_scale * 0.5 * arm_scale * 0.5 * math.cos(math.PI - arm_angles[0]))
		joint_height := math.sqrt(arm_scale * 0.5 * arm_scale * 0.5 - joint_length * 0.5 * joint_length * 0.5) * 2.0

		arm.joint.transform.scale.x = arm_scale
		arm.joint.transform.scale.y = joint_height
		arm.joint.transform.scale.z = joint_length

		arm.joint.transform.rotation.x = math.PI * 0.5 - arm_angles[0] * 0.5

		arm.joint.transform.position.y = -joint_height * 0.5 * math.cos(arm.joint.transform.rotation.x)
		arm.joint.transform.position.z = -shared.GAME_CONSTANTS.upper_arm_length - joint_height * 0.5 * math.sin(arm.joint.transform.rotation.x)

		arm.joint.transform.parent = &arm.anchor
	} else {
		material := basic_material_init()
		material.color = shared.hex_to_vec(shirt_color)

		arm.extender = mesh_init(create_cube_geo(), &material.base)
		arm.extender.transform.parent = &arm.anchor

		arm.extender.transform.scale.x = arm_scale
		arm.extender.transform.scale.z = arm_scale
		arm.extender.transform.scale.y = 20.0

		arm.extender.transform.rotation.x = -math.PI * 0.5 - arm_angles[0]
		arm.extender.transform.position.z = -shared.GAME_CONSTANTS.upper_arm_length
	}

	lower_segments := []Color_Cube_Segment{
		{shirt_color, 0.65, 1.0},
		{sleeve_color, 0.15, 1.1},
		{skin_color, 0.2, 1.0},
	}

	arm.lower = generate_color_cube(arm_scale, shared.GAME_CONSTANTS.lower_arm_length, arm_scale, lower_segments)
	arm.lower.transform.parent = &arm.anchor

	arm.lower.transform.rotation.x = -math.PI * 0.5 - arm_angles[0]

	arm.lower.transform.position.y = -shared.GAME_CONSTANTS.lower_arm_length * 0.5 * math.cos(arm.lower.transform.rotation.x)
	arm.lower.transform.position.z = -shared.GAME_CONSTANTS.upper_arm_length - shared.GAME_CONSTANTS.lower_arm_length * 0.5 * math.sin(arm.lower.transform.rotation.x)

	arm.anchor.position.x = x - weapon.offset.x * left_handed_mlt
	arm.anchor.position.y = y - weapon.offset.y
	arm.anchor.position.z = -weapon.offset.z
	arm.anchor.scale = shared.Vec3{1.0, 1.0, 1.0}

	arm.anchor.rotation.x = -arm_angles[1] + math.atan2(weapon.offset.y + hold.y - y, -(weapon.offset.z - hold.z))
	arm.anchor.rotation.y = math.atan2(x - (weapon.offset.x * left_handed_mlt - hold.x) * (is_left && weapon.akimbo ? -1.0 : 1.0), -(weapon.offset.z - hold.z))
	arm.anchor.rotation_order = .EXTRINSIC

	return arm
}

generate_arms :: proc(weapon: ^shared.Weapon, third_person, left_handed: bool, shirt_color, sleeve_color, skin_color: i32) -> ^Player_Arms {
	arms := new(Player_Arms)

	offset := (-shared.GAME_CONSTANTS.chest_width + shared.GAME_CONSTANTS.arm_scale * 0.5 - shared.GAME_CONSTANTS.arm_inset) * (third_person ? 1.0 : weapon.hold_width != 0 ? weapon.hold_width : 0.4)

	arms.left = generate_arm(offset, shared.GAME_CONSTANTS.arm_offset, weapon, !left_handed, third_person, left_handed, shirt_color, sleeve_color, skin_color)
	arms.right = generate_arm(-offset, shared.GAME_CONSTANTS.arm_offset, weapon, left_handed, third_person, left_handed, shirt_color, sleeve_color, skin_color)

	arms.anchor.position.z += third_person ? 0.0 : weapon.hold_distance_offset

	arms.anchor.scale = shared.Vec3{1.0, 1.0, 1.0}
	arms.left.anchor.parent = &arms.anchor
	arms.right.anchor.parent = &arms.anchor

	return arms
}

generate_head :: proc(skin_color, hair_color: i32) -> ^Color_Cube {
	segments := []Color_Cube_Segment{
		{hair_color, 0.2, 1.0},
		{skin_color, 0.8, 1.0},
	}

	head := generate_color_cube(
		shared.GAME_CONSTANTS.head_scale,
		shared.GAME_CONSTANTS.head_scale,
		shared.GAME_CONSTANTS.head_scale,
		segments,
	)

	if head != nil {
		head.transform.position.y = shared.GAME_CONSTANTS.body_height + shared.GAME_CONSTANTS.head_scale * 0.5
	}

	return head
}

generate_body :: proc(shirt_color, pants_color: i32) -> ^Color_Cube {
	segments := []Color_Cube_Segment{
		{shirt_color, 0.8, 1.0},
		{pants_color, 0.2, 1.05},
	}

	body := generate_color_cube(
		shared.GAME_CONSTANTS.chest_width,
		shared.GAME_CONSTANTS.body_height,
		shared.GAME_CONSTANTS.chest_scale,
		segments,
	)

	if body != nil {
		body.transform.position.y = shared.GAME_CONSTANTS.body_height * 0.5
	}

	return body
}

generate_leg :: proc(is_left: bool, pants_color, shoe_color: i32) -> ^Color_Cube {
	segments := []Color_Cube_Segment{
		{pants_color, 0.75, 1.0},
		{shoe_color, 0.25, 1.0},
	}

	leg := generate_color_cube(shared.GAME_CONSTANTS.leg_scale, shared.GAME_CONSTANTS.leg_height, shared.GAME_CONSTANTS.leg_scale, segments)

	if leg != nil {
		leg.transform.position.x = shared.GAME_CONSTANTS.leg_scale * 0.5 * (is_left ? -1.0 : 1.0)
		leg.transform.position.y = shared.GAME_CONSTANTS.leg_height * 0.5
	}

	return leg
}

generate_crouched_leg :: proc(is_left: bool, pants_color, shoe_color: i32) -> ^Player_Crouched_Leg {
	leg := new(Player_Crouched_Leg)

	leg_angles := [2]f32{2.0, 0.5}

	upper_material := basic_material_init()
	joint_material := basic_material_init()

	upper_material.color = shared.hex_to_vec(pants_color)
	joint_material.color = shared.hex_to_vec(pants_color)

	leg.upper = mesh_init(create_cube_geo(), &upper_material.base)
	leg.joint = mesh_init(create_cube_geo(), &joint_material.base)

	leg.upper.transform.scale.x = shared.GAME_CONSTANTS.leg_scale
	leg.upper.transform.scale.z = shared.GAME_CONSTANTS.leg_scale
	leg.upper.transform.scale.y = shared.GAME_CONSTANTS.leg_height * 0.5

	leg.upper.transform.rotation.x = leg_angles[0]

	leg.upper.transform.position.y = -shared.GAME_CONSTANTS.leg_height * 0.5 * math.cos(leg.upper.transform.rotation.x)
	leg.upper.transform.position.z = -shared.GAME_CONSTANTS.leg_height * 0.5 * math.sin(leg.upper.transform.rotation.x)

	leg.upper.transform.parent = &leg.anchor

	joint_length := math.sqrt(2.0 * shared.GAME_CONSTANTS.leg_scale * 0.5 * shared.GAME_CONSTANTS.leg_scale * 0.5 - 2.0 * shared.GAME_CONSTANTS.leg_scale * 0.5 * shared.GAME_CONSTANTS.leg_scale * 0.5 * math.cos(math.PI - (leg_angles[0] - leg_angles[1])))
	joint_height := math.sqrt(shared.GAME_CONSTANTS.leg_scale * 0.5 * shared.GAME_CONSTANTS.leg_scale * 0.5 - joint_length * 0.5 * joint_length * 0.5) * 2.0

	leg.joint.transform.scale.x = shared.GAME_CONSTANTS.leg_scale
	leg.joint.transform.scale.y = joint_height
	leg.joint.transform.scale.z = joint_length

	leg.joint.transform.rotation.x = (leg_angles[0] + leg_angles[1]) * 0.5

	leg.joint.transform.position.y = -shared.GAME_CONSTANTS.leg_height * 0.5 * math.cos(leg.upper.transform.rotation.x) - joint_height * 0.5 * math.cos(leg.joint.transform.rotation.x)
	leg.joint.transform.position.z = -shared.GAME_CONSTANTS.leg_height * 0.5 * math.sin(leg.upper.transform.rotation.x) - joint_height * 0.5 * math.sin(leg.joint.transform.rotation.x)

	leg.joint.transform.parent = &leg.anchor

	lower_segments := []Color_Cube_Segment{
		{pants_color, 0.5, 1.0},
		{shoe_color, 0.5, 1.0},
	}

	leg.lower = generate_color_cube(shared.GAME_CONSTANTS.leg_scale, shared.GAME_CONSTANTS.leg_height * 0.5, shared.GAME_CONSTANTS.leg_scale, lower_segments)
	leg.lower.transform.parent = &leg.anchor

	leg.lower.transform.rotation.x = leg_angles[1]

	leg.lower.transform.position.y = -shared.GAME_CONSTANTS.leg_height * 0.5 * math.cos(leg.upper.transform.rotation.x) - shared.GAME_CONSTANTS.leg_height * 0.25 * math.cos(leg.lower.transform.rotation.x)
	leg.lower.transform.position.z = -shared.GAME_CONSTANTS.leg_height * 0.5 * math.sin(leg.upper.transform.rotation.x) - shared.GAME_CONSTANTS.leg_height * 0.25 * math.sin(leg.lower.transform.rotation.x)

	leg.anchor.scale = shared.Vec3{1.0, 1.0, 1.0}

	leg.anchor.position.x = shared.GAME_CONSTANTS.leg_scale * 0.5 * (is_left ? -1.0 : 1.0)
	leg.anchor.position.y = shared.GAME_CONSTANTS.leg_height - shared.GAME_CONSTANTS.crouch_distance + 0.5

	leg.anchor.rotation.y = is_left ? math.PI / 8.0 : -math.PI / 6.0

	return leg
}

player_generate_meshes :: proc(player: ^shared.Player, render_you: bool) {
	if player.mesh != nil {
		return
	}

	player.render_you = render_you

	colors := player.game.classes[player.class_index].colors

	third_person := !render_you || player_uses_third_person_camera(player)

	player_mesh := new(Player_Mesh)

	player_mesh.anchor = new(Mesh_Transform)
	player_mesh.body_anchor = new(Mesh_Transform)
	player_mesh.upper_body_anchor = new(Mesh_Transform)

	player_mesh.body_anchor.position.y = shared.GAME_CONSTANTS.leg_height
	player_mesh.body_anchor.parent = player_mesh.anchor
	player_mesh.upper_body_anchor.parent = player_mesh.body_anchor

	player_mesh.anchor.scale = shared.Vec3{1.0, 1.0, 1.0}
	player_mesh.body_anchor.scale = shared.Vec3{1.0, 1.0, 1.0}
	player_mesh.upper_body_anchor.scale = shared.Vec3{1.0, 1.0, 1.0}

	player.mesh = player_mesh

	if player.game.map_inst.config.model != .SPRITE {
		if third_person {
			player_mesh.body = generate_body(colors[1], colors[2])
			player_mesh.head = generate_head(colors[0], colors[4])

			player_mesh.body.transform.parent = player_mesh.body_anchor
			player_mesh.head.transform.parent = player_mesh.body_anchor
		}

		if third_person {
			for i in 0 ..< 2 {
				leg := generate_leg(i == 0, colors[2], colors[3])

				leg.transform.parent = player_mesh.anchor
				player_mesh.legs[i] = leg
			}

			for i in 0 ..< 2 {
				leg := generate_crouched_leg(i == 0, colors[2], colors[3])

				leg.anchor.parent = player_mesh.anchor
				player_mesh.crouched_legs[i] = leg
			}
		}

		for i in 0 ..< player.loadout_size {
			weapon := player.game.weapons[player.loadout[i]]

			arms := generate_arms(weapon, third_person, player.left_handed, colors[1], colors[5], colors[0])
			if arms == nil {
				continue
			}

			arms.anchor.parent = player_mesh.upper_body_anchor
			append(&player_mesh.arms, arms)

			// melee mesh
			if weapon.melee {
				model_path := shared.concat(shared.assets_path(), "models/melee/melee_0.obj")
				texture_path := shared.concat(shared.assets_path(), "textures/melee/melee_0.png")
				defer delete(model_path)
				defer delete(texture_path)

				melee_geo := load_obj_model(model_path, false)
				melee_texture := load_texture(texture_path)

				if melee_geo != nil && melee_texture != 0 {
					melee_mat := basic_material_init()
					melee := mesh_init(melee_geo, &melee_mat.base)

					melee_mat.texture = melee_texture
					melee.transform.parent = &arms.anchor

					melee.transform.position.x = render_you ? 0.9 : 1.7
					melee.transform.position.y = render_you ? -0.95 : -0.4
					melee.transform.position.z = render_you ? 0.72 : 1.2

					melee.transform.rotation.x = -math.PI / 3.5
					melee.transform.rotation.y = render_you ? 0.3 : math.PI * 0.5
					melee.transform.rotation.z = math.PI * -0.9

					arms.weapon_right = melee
				} else {
					geometry_release(melee_geo)
					texture_release(melee_texture)
				}
			}

			// weapon model
			if len(weapon.src) > 0 || len(weapon.model) > 0 {
				for j in 0 ..< 2 {
					model_path: string
					if len(weapon.model) > 0 {
						model_path = shared.concat(shared.assets_path(), weapon.model)
					} else {
						model_src := weapon.src
						if model_src == "weapon-7" {
							model_src = "weapon_7"
						}
						model_path = shared.concat(shared.assets_path(), fmt_tprintf("models/weapons/%s.obj", model_src))
					}

					texture_path: string
					if len(weapon.texture) > 0 {
						texture_path = shared.concat(shared.assets_path(), weapon.texture)
					} else {
						texture_src := weapon.src
						// The configured LMG source follows the old asset naming
						// convention, while the unpacked mod uses weapon_7.
						if texture_src == "weapon-7" {
							texture_src = "weapon_7"
						}
						texture_path = shared.concat(shared.assets_path(), fmt_tprintf("textures/weapons/%s.png", texture_src))
					}
					defer delete(model_path)
					defer delete(texture_path)

					weapon_geo := load_obj_model(model_path, false)
					weapon_tex := load_texture(texture_path)

					if weapon_geo == nil {
						texture_release(weapon_tex)
						continue
					}

					weapon_mat := basic_material_init()
					weapon_mesh := mesh_init(weapon_geo, &weapon_mat.base)

					weapon_mat.texture = weapon_tex

					weapon_mesh.transform.position.x = j == 1 ? weapon.offset.x * -2.0 : 0.0
					weapon_mesh.transform.position.y = 0.0
					weapon_mesh.transform.position.z = 0.0

					weapon_mesh.transform.scale.x = weapon.scale
					weapon_mesh.transform.scale.y = weapon.scale
					weapon_mesh.transform.scale.z = weapon.scale

					weapon_mesh.transform.rotation.y = weapon.rotation != 0 ? weapon.rotation : math.PI * 0.5
					weapon_mesh.transform.parent = &arms.anchor

					if j == 1 {
						arms.weapon_left = weapon_mesh
					} else {
						arms.weapon_right = weapon_mesh
					}

					if !weapon.akimbo {
						break
					}
				}
			}
		}
	}
}

fmt_tprintf :: proc(format: string, args: ..any) -> string {
	return fmt.tprintf(format, ..args)
}

player_uses_third_person_camera :: proc(player: ^shared.Player) -> bool {
	if player == nil || player.game == nil || player.game.map_inst == nil {
		return false
	}

	offset := player.game.map_inst.config.cam_offset
	return player.game.config.third_person || offset.x != 0 || offset.y != 0 || offset.z != 0
}

player_update_meshes :: proc(player: ^shared.Player, is_preview: bool) {
	if player.mesh == nil {
		return
	}

	player_mesh := cast(^Player_Mesh)player.mesh

	animate_aim := true
	weapon_bobbing_mlt: f32 = 1.0
	weapon_lean_mlt: f32 = 1.0
	weapon_rotation: f32 = 0.0
	weapon_offset_mlt := shared.Vec3{1.0, 1.0, 1.0}

	third_person := player_uses_third_person_camera(player)
	aim_val_mlt: f32 = animate_aim && player.is_you ? player.aim_val : 0.0
	aim_mlt: f32 = player.weapon.animate_while_aiming ? 0.0 : aim_val_mlt
	anim_mlt := (1.0 - (1.0 - shared.GAME_CONSTANTS.aim_anim_mlt) * aim_val_mlt) * shared.GAME_CONSTANTS.anim_mlt * weapon_bobbing_mlt
	anim_mlt_crouch := 1.0 - player.crouch_val * 0.8
	anim_mlt_lean := player.render_you ? 1.0 - aim_val_mlt * shared.GAME_CONSTANTS.anim_mlt : 0.0
	recoil_y_mlt := 1.0 - (player.weapon.recoil_y_mlt != 0 ? player.weapon.recoil_y_mlt : 1.0) * shared.GAME_CONSTANTS.anim_mlt
	recoil_z_mlt := 1.0 - (player.weapon.recoil_z_mlt != 0 ? player.weapon.recoil_z_mlt : 0.5) * aim_mlt
	anim_rotate_mlt := (1.0 - (player.weapon.z_rotation != 0 ? player.weapon.z_rotation : 0.3) * aim_mlt) * (player.weapon.z_rotation_mlt != 0 ? player.weapon.z_rotation_mlt : 1.0) * weapon_bobbing_mlt
	anim_y_mlt := 1.0 - (player.weapon.jump_y_mlt != 0 ? player.weapon.jump_y_mlt : 1.0) * aim_mlt
	lean_aim_mlt := 1.0 * aim_mlt * 0.45
	bob_anim_y := player.bob_anim.y * 0.9 * anim_y_mlt * anim_mlt_lean * weapon_bobbing_mlt
	land_bob_y := (player.land_bob_y * (player.weapon.land_bob != 0 ? player.weapon.land_bob : 1.0) * 0.6) * (1.0 - aim_mlt * 0.75) * weapon_bobbing_mlt

	if player.land_bob_yr != land_bob_y {
		player.land_bob_yr += (land_bob_y - player.land_bob_yr) * 0.1
	}

	land_bob_ya := player.land_bob_y * (player.weapon.land_bob != 0 ? player.weapon.land_bob : 1.0) * 0.1
	bob_crouch_mlt := 1.0 - player.crouch_val * 0.5
	jump_rotate := player.jump_rotate * bob_crouch_mlt * anim_mlt_lean * weapon_bobbing_mlt

	if player.jump_rotate_mlt != jump_rotate {
		player.jump_rotate_mlt += (jump_rotate - player.jump_rotate_mlt) * 0.08
	}

	jump_bob_y := player.jump_bob_y * (player.weapon.jump_y_mlt != 0 ? player.weapon.jump_y_mlt : 1.0) * anim_mlt_lean * bob_crouch_mlt * weapon_bobbing_mlt
	recoil_aim_mlt := 1.0 - aim_mlt * 0.89
	recoil_mlt := 1.0 - (player.weapon.aim_recoil_mlt != 0 ? player.weapon.aim_recoil_mlt : 1.0) * aim_mlt
	step_mlt := is_preview ? 0.05 : shared.GAME_CONSTANTS.step_anim
	step_anim := math.sin(player.step_val) * step_mlt
	step_half := math.cos(2.0 * player.step_val) * 0.5 * step_mlt
	step_anim_rotate := -math.sin(player.step_chase) * step_mlt
	step_half_rotate := -math.cos(2.0 * player.step_chase) * 0.5 * step_mlt
	aim_val := third_person ? 0.0 : aim_val_mlt
	aim_lean := (aim_val <= 0.5 ? aim_val : 0.5 - (aim_val - 0.5)) * 0.5
	swap_anim := player.swap_timer / player.weapon.swap_time
	left_hand_mlt: f32 = player.left_handed ? -1.0 : 1.0

	weapon_offset := shared.Vec3{
		player.weapon.offset.x * (player.render_you ? weapon_offset_mlt.x : 1.0) * left_hand_mlt,
		player.weapon.offset.y * (player.render_you ? weapon_offset_mlt.y : 1.0),
		player.weapon.offset.z * (player.render_you ? weapon_offset_mlt.z : 1.0),
	}

	reload_anim: f32 = 0
	if player.reload_timer > 0.0 {
		reload_anim = 1.0 - player.reload_timer / (player.weapon.reload_time * player.game.config.reload_speed)
	}
	if reload_anim > 0.5 {
		reload_anim = 1.0 - reload_anim
	}

	reload_anim *= player.render_you ? 1.0 : 0.3

	idle_anim := (1.0 - aim_val_mlt * 0.88) * 1.75 * weapon_bobbing_mlt
	step_y := player.render_you && !third_person ? abs(step_anim_rotate * 0.5) * anim_mlt_lean : abs(step_anim * 3.5)
	step_yaw := player.render_you ? (third_person ? -step_anim * 0.5 : 0.0) : -step_anim * 2.0

	// Every entity's root follows its authoritative position. Previously this
	// was restricted to the local/preview player, leaving network peers moving
	// and rotating at the world origin despite receiving correct snapshots.
	player_mesh.anchor.position = player.position
	player_mesh.anchor.position.y += step_y

	if player.game.map_inst.config.model != .SPRITE {
		player_mesh.anchor.rotation.y = player.direction.y + step_yaw
	}

	step_half -= step_half * player.crouch_val * shared.GAME_CONSTANTS.crouch_anim_mlt
	step_anim -= step_anim * player.crouch_val * shared.GAME_CONSTANTS.crouch_anim_mlt

	if !player.render_you {
		for i in 0 ..< 4 {
			if i < 2 {
				if player_mesh.legs[i] != nil {
					player_mesh.legs[i].transform.rotation.x = step_anim * (i == 1 ? 1.0 : -1.0) * 7.0
				}
			} else {
				if player_mesh.crouched_legs[i - 2] != nil {
					player_mesh.crouched_legs[i - 2].anchor.rotation.x = step_anim * (i == 3 ? 1.0 : -1.0) * 7.0 + -0.6
				}
			}
		}
	}

	// Shared weapon swapping cannot manipulate client meshes. Keep all loadout
	// arms hidden except the active slot here so swaps remain renderer-agnostic.
	for arms, i in player_mesh.arms {
		if arms == nil {
			continue
		}

		visible := i == int(player.loadout_index)

		if arms.weapon_right != nil {
			arms.weapon_right.visible = visible
		}
		if arms.weapon_left != nil {
			arms.weapon_left.visible = visible
		}

		arm_meshes := [2]^Player_Arm_Mesh{arms.left, arms.right}
		for arm in arm_meshes {
			if arm == nil {
				continue
			}

			if arm.extender != nil {
				arm.extender.visible = visible
			}
			if arm.upper != nil {
				arm.upper.visible = visible
			}
			if arm.joint != nil {
				arm.joint.visible = visible
			}

			for mesh in arm.lower.meshes {
				mesh.visible = visible
			}
		}
	}

	reload_mlt: f32 = third_person ? 0.4 : 1.0
	// The camera already receives local recoil. Applying the same pitch to the
	// first-person mesh cancels the weapon kick in camera space.
	mesh_recoil_pitch := player.recoil_anim_y * shared.GAME_CONSTANTS.recoil_mlt
	if player.render_you && !third_person {
		mesh_recoil_pitch = 0
	}

	player_mesh.upper_body_anchor.rotation.x = bob_anim_y * -0.2 + land_bob_ya + reload_anim * (reload_mlt * -2.8) +
		player.direction.x * (player.render_you && !third_person ? 1.0 : 0.5) +
		(-math.PI * 0.25 * swap_anim + mesh_recoil_pitch) +
		(player.weapon.y_rotation != 0 ? player.weapon.y_rotation : 0.0)

	player_mesh.upper_body_anchor.rotation.y = reload_anim * -reload_mlt
	player_mesh.upper_body_anchor.rotation.z = 0.35 * weapon_rotation

	player_mesh.upper_body_anchor.position.x = 0.0
	player_mesh.upper_body_anchor.position.z = player.render_you && !third_person ? player.recoil_anim_y * 0.08 * recoil_mlt : 0.0
	player_mesh.upper_body_anchor.position.y = player.recoil_anim_y * (player.weapon.recoil_y_mlt != 0 ? player.weapon.recoil_y_mlt : 0.3) * recoil_y_mlt + (player.render_you && !third_person ? player.height : shared.GAME_CONSTANTS.player_height) - shared.GAME_CONSTANTS.camera_height - shared.GAME_CONSTANTS.leg_height

	if player.loadout_index < 0 || player.loadout_index >= i32(len(player_mesh.arms)) || player_mesh.arms[player.loadout_index] == nil {
		return
	}

	arm_anchor := &player_mesh.arms[player.loadout_index].anchor

	arm_anchor.rotation.x = -math.cos(player.idle_anim) * bob_crouch_mlt * 0.01 * idle_anim +
		player.weapon.rotation_offset * anim_mlt_lean + player.weapon.rotation_offset_aim * (1.0 - anim_mlt_lean) -
		player.land_bob_yr * 0.4 +
		player.lean_anim.y * lean_aim_mlt * (player.weapon.lean_mlt != 0 ? player.weapon.lean_mlt : 1.0) * weapon_lean_mlt +
		step_half_rotate * -0.9 * anim_mlt

	arm_anchor.rotation.y = player.jump_rotate_mlt * 0.2 +
		player.lean_anim.x * lean_aim_mlt * (player.weapon.lean_mlt != 0 ? player.weapon.lean_mlt : 1.0) * weapon_lean_mlt +
		(-step_anim_rotate * 0.16 * anim_mlt_lean * anim_mlt_crouch + player.lean_anim.z * 0.2) * anim_mlt

	arm_anchor.rotation.z = jump_rotate + aim_lean +
		player.lean_anim.z * 0.7 * anim_rotate_mlt +
		player.weapon.crouch_lean * left_hand_mlt * player.crouch_val * anim_mlt_lean * anim_mlt

	arm_anchor.position.x = player.recoil.x * recoil_aim_mlt -
		player.jump_rotate_mlt * anim_mlt_lean * 1.3 +
		(player.lean_anim.z * 0.35 - player.weapon.crouch_rotation * left_hand_mlt * player.crouch_val * anim_mlt_lean + step_anim * 0.5 * anim_mlt_crouch * anim_mlt_lean) * aim_val_mlt * anim_mlt +
		weapon_offset.x - (weapon_offset.x - player.weapon.origin.x * left_hand_mlt) * aim_val

	arm_anchor.position.y = player.recoil.z * recoil_aim_mlt +
		math.sin(player.idle_anim) * 0.02 * idle_anim +
		jump_bob_y + land_bob_y * 0.5 - bob_anim_y * 1.5 -
		(player.weapon.bomb ? player.interact_progress * 3.0 : 0.0) +
		(step_half * 0.85 - player.weapon.crouch_drop * player.crouch_val * anim_mlt_lean) * anim_mlt +
		weapon_offset.y - (weapon_offset.y - player.weapon.origin.y) * aim_val

	arm_anchor.position.z = weapon_offset.z - (weapon_offset.z - player.weapon.origin.z) * aim_val +
		player.bob_anim.z * anim_mlt + player.recoil_anim * player.weapon.recoil_z * recoil_z_mlt

	if !player.render_you || third_person {
		crouch_distance := shared.GAME_CONSTANTS.crouch_distance * player.crouch_val
		crouch_lean := shared.GAME_CONSTANTS.crouch_lean * player.crouch_val

		player_mesh.body_anchor.rotation.y = 0.0
		player_mesh.body_anchor.rotation.z = 0.0
		player_mesh.body_anchor.rotation.x = crouch_lean + player.direction.x * 0.5

		player_mesh.upper_body_anchor.rotation.x -= crouch_lean

		player_mesh.body_anchor.position.x = 0.0
		player_mesh.body_anchor.position.z = 0.0
		player_mesh.body_anchor.position.y = shared.GAME_CONSTANTS.leg_height - crouch_distance

		for leg in player_mesh.legs {
			if leg == nil {
				continue
			}

			for mesh in leg.meshes {
				mesh.visible = player.crouch_val == 0
			}
		}

		for leg in player_mesh.crouched_legs {
			if leg == nil {
				continue
			}

			leg.upper.visible = player.crouch_val != 0
			leg.joint.visible = player.crouch_val != 0

			for mesh in leg.lower.meshes {
				mesh.visible = player.crouch_val != 0
			}
		}
	}
}

player_meshes_fini :: proc(player: ^shared.Player) {
	if player.mesh == nil {
		return
	}

	player_mesh := cast(^Player_Mesh)player.mesh

	if player_mesh.body != nil {
		for mesh in player_mesh.body.meshes {
			mesh_fini(mesh)
		}

		delete(player_mesh.body.meshes)
		free(player_mesh.body)
	}

	if player_mesh.head != nil {
		for mesh in player_mesh.head.meshes {
			mesh_fini(mesh)
		}

		delete(player_mesh.head.meshes)
		free(player_mesh.head)
	}

	for arms in player_mesh.arms {
		if arms == nil {
			continue
		}

		if arms.weapon_right != nil {
			mesh_fini(arms.weapon_right)
		}
		if arms.weapon_left != nil {
			mesh_fini(arms.weapon_left)
		}

		for j in 0 ..< 2 {
			arm := arms.left if j == 1 else arms.right

			if arm == nil {
				continue
			}

			if arm.extender != nil {
				mesh_fini(arm.extender)
			}

			if arm.upper != nil {
				mesh_fini(arm.upper)
			}
			if arm.joint != nil {
				mesh_fini(arm.joint)
			}

			for mesh in arm.lower.meshes {
				mesh_fini(mesh)
			}

			delete(arm.lower.meshes)
			free(arm.lower)
			free(arm)
		}

		free(arms)
	}

	delete(player_mesh.arms)

	for leg in player_mesh.legs {
		if leg == nil {
			continue
		}

		for mesh in leg.meshes {
			mesh_fini(mesh)
		}

		delete(leg.meshes)
		free(leg)
	}

	for leg in player_mesh.crouched_legs {
		if leg == nil {
			continue
		}

		mesh_fini(leg.upper)
		mesh_fini(leg.joint)

		for mesh in leg.lower.meshes {
			mesh_fini(mesh)
		}

		delete(leg.lower.meshes)
		free(leg.lower)
		free(leg)
	}

	free(player_mesh.upper_body_anchor)
	free(player_mesh.body_anchor)
	free(player_mesh.anchor)
	free(player_mesh)

	player.mesh = nil
}
