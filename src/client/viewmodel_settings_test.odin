package main

import "core:math"
import "core:testing"
import menuui "../menu"
import shared "../shared"

when ODIN_TEST {
	@(test)
	viewmodel_preview_cancel_and_camera :: proc(t: ^testing.T) {
		client := Client{viewmodel_settings=menuui.DEFAULT_VIEWMODEL_SETTINGS, camera=camera_init(math.PI/2)}
		view := menuui.View{viewmodel=client.viewmodel_settings, fov=90}
		client.menu.page = .SETTINGS
		menuui.prepare_settings(&client.menu, view)
		menuui.activate(&client.menu, {action={kind=.VIEWMODEL_VALUE, index=i32(menuui.Viewmodel_Control.WEAPON_FOV), value=110}})
		menuui.activate(&client.menu, {action={kind=.VIEWMODEL_TOGGLE, index=i32(menuui.Viewmodel_Toggle.SHOW_HANDS)}})
		menuui.activate(&client.menu, {action={kind=.FOV, value=105}})
		preview := client_viewmodel_values(&client)
		weapon_camera := camera_for_viewmodel(&client.camera, preview)
		testing.expect(t, abs(weapon_camera.fov-110*math.PI/180)<1e-6 && !preview.toggles[.SHOW_HANDS] && abs(client_world_fov(&client)-105*math.PI/180)<1e-6,
			"the draft must preview both camera FOVs and hand visibility")
		testing.expect(t, client.viewmodel_settings == menuui.DEFAULT_VIEWMODEL_SETTINGS && client.camera.fov == math.PI/2,
			"previewing must preserve committed settings")
		menuui.activate(&client.menu, {action={kind=.SETTINGS_CANCEL}})
		testing.expect(t, client_viewmodel_values(&client) == menuui.DEFAULT_VIEWMODEL_SETTINGS && client_world_fov(&client) == math.PI/2,
			"Cancel must immediately restore both camera and model preferences")
		invalid := menuui.DEFAULT_VIEWMODEL_SETTINGS
		invalid.values[.BOBBING], invalid.values[.LEANING], invalid.values[.WEAPON_FOV] = math.nan_f32(), 99, math.inf_f32(1)
		valid := menuui.viewmodel_settings_validate(invalid)
		testing.expect(t, valid.values[.BOBBING] == 1 && valid.values[.LEANING] == 6 && valid.values[.WEAPON_FOV] == 95,
			"invalid preferences must never produce nonfinite or unbounded transforms")
	}

	@(test)
	viewmodel_ads_input_and_zoom :: proc(t: ^testing.T) {
		client := Client{viewmodel_settings=menuui.DEFAULT_VIEWMODEL_SETTINGS, sensitivity=1, ads_sensitivity=0.5, mouse_dpi=800}
		testing.expect(t, client_aim_input(&client, true, true) && !client_aim_input(&client, false, true), "hold ADS must follow the binding")
		client.viewmodel_settings.toggles[.TOGGLE_ADS] = true
		testing.expect(t, client_aim_input(&client, true, true) && client_aim_input(&client, true, true) && client_aim_input(&client, false, true),
			"toggle ADS must latch on one press without retriggering while held")
		testing.expect(t, !client_aim_input(&client, true, true) && !client_aim_input(&client, false, true), "the next press must release ADS")
		client_aim_input(&client, true, true)
		testing.expect(t, !client_aim_input(&client, true, false) && !client_aim_input(&client, true, true),
			"menus, freecam and death must clear the latch without treating a held binding as a fresh press")
		client_aim_input(&client, false, true)
		testing.expect(t, client_aim_input(&client, true, true), "a new press after resuming must work")
		weapon := shared.Weapon{zoom=3}
		player := shared.Player{weapon=&weapon, aim_val=1}
		client.me = &player
		client.advanced_sensitivity = true
		for power in ([3]f32{0,0.5,1}) {
			client.viewmodel_settings.values[.ADS_FOV_POWER] = power
			client.camera.zoom = viewmodel_zoom(weapon.zoom, 1, client.viewmodel_settings)
			testing.expect(t, client.camera.zoom == 1+2*power, "ADS FOV power must blend zoom from hipfire to the weapon's full zoom")
			camera := camera_for_viewmodel(&client.camera, client.viewmodel_settings)
			testing.expect(t, camera.zoom == client.camera.zoom, "world and weapon cameras must share ADS zoom")
			testing.expect(t, abs(client_mouse_rotation(&client, {1,0}).x-shared.GAME_CONSTANTS.mouse_sensitivity*0.5)<1e-6,
				"explicit ADS sensitivity must remain correct even with ADS zoom disabled")
		}
	}

	@(test)
	viewmodel_weapon_visibility_and_handedness :: proc(t: ^testing.T) {
		map_inst: shared.Map
		game := shared.Game{map_inst=&map_inst, config=shared.DEFAULT_GAME_CONFIG}
		weapon := shared.Weapon{offset={2,-3,4}, origin={0,-1,2}, swap_time=1, reload_time=1}
		root := Mesh_Transform{scale={1,1,1}}
		body := Mesh_Transform{parent=&root, scale={1,1,1}}
		upper := Mesh_Transform{parent=&body, scale={1,1,1}}
		gun, other_gun, sight, hand, muzzle: Mesh
		lower: Color_Cube
		append(&lower.meshes, &hand)
		defer delete(lower.meshes)
		right, left := Player_Arm_Mesh{lower=&lower}, Player_Arm_Mesh{lower=&lower}
		arms := Player_Arms{anchor={parent=&upper, scale={1,1,1}}, right=&right, left=&left, weapon_right=&gun, weapon_left=&other_gun, attachment=&sight}
		right.anchor = {parent=&arms.anchor, scale={1,1,1}}
		right.pivot = {parent=&right.anchor, scale={1,1,1}}
		for mesh in ([5]^Mesh{&gun, &other_gun, &sight, &hand, &muzzle}) {
			mesh.transform = {parent=&arms.anchor, position={0.3,0.4,-0.5}, scale={1,1,1}}
		}
		hand.transform.parent = &right.pivot
		rig := Player_Mesh{anchor=&root, body_anchor=&body, upper_body_anchor=&upper}
		append(&rig.arms, &arms)
		defer delete(rig.arms)
		player := shared.Player{game=&game, weapon=&weapon, mesh=rawptr(&rig), is_you=true, render_you=true, active=true, loadout_size=1, can_throw=true}
		client := Client{me=&player, viewmodel_settings=menuui.DEFAULT_VIEWMODEL_SETTINGS}
		client.viewmodel_settings.values[.BOBBING], client.viewmodel_settings.values[.LEANING] = 0, 0
		previous_client := g_client
		g_client = &client
		defer { g_client = previous_client }
		// Exercise all categories in the same slot, including the melee visibility
		// override that normally restores the knife while it can be thrown.
		for category in ([3]menuui.Viewmodel_Toggle{.SHOW_PRIMARY,.SHOW_SECONDARY,.SHOW_MELEE}) {
			weapon.secondary, weapon.melee = category == .SHOW_SECONDARY, category == .SHOW_MELEE
			client.viewmodel_settings.toggles[category] = false
			player_update_meshes(&player, false)
			testing.expect(t, !gun.visible && !other_gun.visible && !sight.visible && !hand.visible,
				"hiding a weapon category must hide both guns, its attachment and hands, even for a throwable knife")
			client.viewmodel_settings.toggles[category] = true
			player_update_meshes(&player, false)
			testing.expect(t, gun.visible && other_gun.visible && sight.visible && hand.visible, "restoring a category must restore the active rig")
		}
		weapon.secondary, weapon.melee = false, false
		client.viewmodel_settings.toggles[.SHOW_PRIMARY] = false
		player.aim_val = 1
		player_update_meshes(&player, false)
		testing.expect(t, !gun.visible && player.aim_val == 1, "aiming must not reveal a hidden primary or change gameplay ADS")
		client.viewmodel_settings.toggles[.SHOW_PRIMARY] = true
		player.aim_val = 0
		player_update_meshes(&player, false)
		meshes := [5]^Mesh{&gun, &other_gun, &sight, &hand, &muzzle}
		right_positions: [5]shared.Vec4
		for mesh, i in meshes {
			mesh_update_transform_matrix(mesh)
			right_positions[i] = mesh.transform_matrix * shared.Vec4{0,0,0,1}
		}
		client.viewmodel_settings.toggles[.LEFT_HANDED] = true
		for _ in 0..<2 {
			player_update_meshes(&player, false)
			for mesh, i in meshes {
				mesh_update_transform_matrix(mesh)
				position := mesh.transform_matrix * shared.Vec4{0,0,0,1}
				testing.expect(t, abs(position.x+right_positions[i].x)<1e-6 && abs(position.y-right_positions[i].y)<1e-6 && abs(position.z-right_positions[i].z)<1e-6,
					"left handed must mirror guns, sights, hands and muzzle positions consistently across frames")
			}
		}
		client.viewmodel_settings.toggles[.LEFT_HANDED] = false
		player_update_meshes(&player, false)
		check_mesh_point(t, &gun, {0,0,0,1}, right_positions[0])
		testing.expect(t, !player.left_handed && player.loadout_index == 0, "handedness is a presentation preference and must preserve player state")
		client.viewmodel_settings.toggles[.LEFT_HANDED], client.viewmodel_settings.toggles[.SHOW_PRIMARY] = true, false
		player_update_meshes(&player, true)
		testing.expect(t, upper.scale.x == 1 && gun.visible && hand.visible, "preview rigs must ignore local visibility and handedness")
		game.config.third_person = true
		player_update_meshes(&player, false)
		testing.expect(t, upper.scale.x == 1 && gun.visible && hand.visible, "third person must ignore local visibility and handedness")
		game.config.third_person = false
		player.render_you, player.is_you = false, false
		player_update_meshes(&player, false)
		testing.expect(t, upper.scale.x == 1 && gun.visible && hand.visible, "remote models must ignore local visibility and handedness")
	}

	@(test)
	viewmodel_settings_drive_only_local_first_person_rig :: proc(t: ^testing.T) {
		map_inst: shared.Map
		game := shared.Game{map_inst=&map_inst, config=shared.DEFAULT_GAME_CONFIG}
		weapon := shared.Weapon{offset={2,-3,4}, origin={0,-1,2}, swap_time=1, reload_time=1, has_attachment=true}
		root, body, upper: Mesh_Transform
		gun, hand: Mesh
		lower: Color_Cube
		append(&lower.meshes, &hand)
		defer delete(lower.meshes)
		right := Player_Arm_Mesh{lower=&lower}
		arms := Player_Arms{weapon_right=&gun, right=&right}
		rig := Player_Mesh{anchor=&root, body_anchor=&body, upper_body_anchor=&upper}
		append(&rig.arms, &arms)
		defer delete(rig.arms)
		player := shared.Player{game=&game, weapon=&weapon, mesh=rawptr(&rig), is_you=true, render_you=true, active=true, loadout_size=1}
		client := Client{me=&player, viewmodel_settings=menuui.DEFAULT_VIEWMODEL_SETTINGS}
		previous_client := g_client
		g_client = &client
		defer { g_client = previous_client }
		client.viewmodel_settings.values[.BOBBING], client.viewmodel_settings.values[.LEANING] = 0, 0
		client.viewmodel_settings.values[.OFFSET_X], client.viewmodel_settings.values[.OFFSET_Y], client.viewmodel_settings.values[.OFFSET_Z] = 2, 3, 4
		player_update_meshes(&player, false)
		testing.expect(t, arms.anchor.position == (shared.Vec3{4,-9,16}) && gun.visible && hand.visible, "global offsets must scale the local hipfire model")
		player.aim_val = 1
		client.viewmodel_settings.values[.ADS_OFFSET_Y] = 2
		player_update_meshes(&player, false)
		testing.expect(t, abs(arms.anchor.position.y-(weapon.origin.y-2*REFLEX_SIGHT_AIM_OFFSET_Y))<1e-6 && arms.anchor.position.x == weapon.origin.x,
			"ADS Y must adjust the sight offset while hipfire offsets converge to the ADS origin")
		client.viewmodel_settings.toggles[.AIM_ANIMATION] = false
		player_update_meshes(&player, false)
		testing.expect(t, arms.anchor.position == (shared.Vec3{4,-9,16}) && player.aim_val == 1, "disabling aim animation must keep the hipfire pose without changing gameplay ADS")
		client.viewmodel_settings.toggles[.HIDE_ON_ADS] = true
		player_update_meshes(&player, false)
		testing.expect(t, !gun.visible && !hand.visible, "hide on ADS must hide the first-person rig independently of aim animation")
		player.aim_val = 0
		client.viewmodel_settings.toggles[.SHOW_HANDS] = false
		player_update_meshes(&player, false)
		testing.expect(t, gun.visible && !hand.visible, "hiding hands must leave the weapon visible")
		client.viewmodel_settings.values[.ROTATION] = 0.5
		client.viewmodel_settings.values[.SWAP_Y] = 2
		player.swap_timer = 0.5
		player_update_meshes(&player, false)
		testing.expect(t, abs(upper.rotation.z-0.175)<1e-6 && abs(upper.rotation.x+math.PI/4)<1e-6, "rotation and swap Y must affect the weapon rig")
		player.swap_timer, player.reload_timer = 0, 0.75
		client.viewmodel_settings.values[.RELOAD_Y] = 0
		player_update_meshes(&player, false)
		testing.expect(t, upper.rotation.x == 0 && upper.rotation.y == 0, "reload Y zero must suppress the lowering animation")
		client.viewmodel_settings.values[.RELOAD_Y] = 1
		player_update_meshes(&player, false)
		testing.expect(t, abs(upper.rotation.x+0.7)<1e-6 && abs(upper.rotation.y+0.25)<1e-6, "reload Y one must preserve the normal lowering animation")
		player.reload_timer = 0
		player.lean_anim = {0.3,0.2,0.1}
		client.viewmodel_settings.values[.LEANING] = 2
		player_update_meshes(&player, false)
		testing.expect(t, abs(arms.anchor.rotation.x-0.4)<1e-6 && abs(arms.anchor.rotation.y-0.6)<1e-6, "weapon leaning must scale mouse movement sway")
		player.lean_anim, player.bob_anim = {}, {0,0,0.4}
		client.viewmodel_settings.values[.BOBBING] = 2
		player_update_meshes(&player, false)
		testing.expect(t, abs(arms.anchor.position.z-(16+0.8*shared.GAME_CONSTANTS.anim_mlt))<1e-6, "weapon bobbing must scale movement animation")
		player.render_you, player.is_you = false, false
		player_update_meshes(&player, false)
		testing.expect(t, upper.rotation.z == 0 && gun.visible && hand.visible && arms.anchor.position.x == weapon.offset.x, "local preferences must not alter remote world models")
	}
}
