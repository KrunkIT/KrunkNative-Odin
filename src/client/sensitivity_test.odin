package main

import "core:math"
import "core:testing"
import menuui "../menu"
import shared "../shared"

when ODIN_TEST {
	@(test)
	ads_sensitivity_and_inversion_drive_mouse_rotation :: proc(t: ^testing.T) {
		weapon := shared.Weapon{zoom = 2}
		player := shared.Player{weapon = &weapon, aim_val = 1}
		client := Client{me = &player, mouse_dpi = 1600, advanced_sensitivity = true}
		client.sensitivity = menuui.sensitivity_from_cm360(40, client.mouse_dpi)
		client.ads_sensitivity = menuui.sensitivity_from_cm360(60, client.mouse_dpi)
		for fov in ([3]f32{60,90,120}) {
			client.camera.fov = fov*math.PI/180
			for zoom in ([3]f32{1,2,4}) {
				weapon.zoom, client.camera.zoom = zoom, zoom
				ads_counts := 60*client.mouse_dpi/2.54
				delta := shared.Vec2{ads_counts, ads_counts}
				rotation := client_mouse_rotation(&client, delta)
				testing.expect(t, abs(rotation.x-2*math.PI)<0.00001 && abs(rotation.y-2*math.PI)<0.00001, "fully aimed ADS must use its exact cm/360 at every FOV and weapon zoom")
				client.invert_mouse = true
				inverted := client_mouse_rotation(&client, delta)
				testing.expect(t, inverted.x == rotation.x && inverted.y == -rotation.y, "invert mouse must reverse only vertical look, including ADS")
				client.invert_mouse = false
			}
		}
		weapon.zoom, client.camera.zoom, player.aim_val = 2, 1, 0
		hip_counts := 40*client.mouse_dpi/2.54
		testing.expect(t, abs(client_mouse_rotation(&client, {hip_counts,0}).x-2*math.PI)<0.00001, "hipfire must keep its own physical sensitivity")
		client.camera.zoom = 1.5
		transition := client_mouse_rotation(&client, {1,0}).x
		testing.expect(t, abs(transition-shared.GAME_CONSTANTS.mouse_sensitivity*(client.sensitivity+client.ads_sensitivity)*0.5)<0.000001, "ADS transitions must blend smoothly between the two sensitivities")
		client.advanced_sensitivity = false
		client.camera.zoom = 2
		testing.expect(t, client_mouse_rotation(&client, {1,0}).x == shared.GAME_CONSTANTS.mouse_sensitivity*client.sensitivity/2, "disabling Advanced must restore existing weapon zoom scaling")
	}

	@(test)
	fov_changes_preserve_physical_sensitivity :: proc(t: ^testing.T) {
		client := Client{mouse_dpi = 1600}
		client.sensitivity = menuui.sensitivity_from_cm360(35.5, client.mouse_dpi)
		original_factor := client.sensitivity
		client.menu.page = .SETTINGS
		menuui.prepare_settings(&client.menu, {sensitivity = client.sensitivity, mouse_dpi = client.mouse_dpi, fov = 90})
		for fov in ([5]f32{60,75,90,105,120}) {
			menuui.activate(&client.menu, {action = {kind = .FOV, value = fov}})
			testing.expect(t, client.menu.settings_draft.sensitivity == original_factor, "moving the FOV slider must preserve the sensitivity draft")
			menu_apply_action(&client, {kind = .SETTINGS_SAVE})
			testing.expect(t, abs(client.camera.fov - fov*math.PI/180) < 0.000001, "FOV changes must reach the world camera")
			testing.expect(t, client.sensitivity == original_factor && abs(menuui.cm360_from_sensitivity(client.sensitivity, client.mouse_dpi)-35.5) < 0.0001,
				"applying any supported FOV must preserve true hipfire cm/360")
		}
	}

	@(test)
	sensitivity_matches_physical_distance :: proc(t: ^testing.T) {
		for dpi in ([5]f32{400,800,1600,3200,32000}) {
			for cm in ([5]f32{0.1,10,35.5,100,2000}) {
				factor := menuui.sensitivity_from_cm360(cm, dpi)
				counts := cm*dpi/2.54
				rotation := counts*shared.GAME_CONSTANTS.mouse_sensitivity*factor
				testing.expect(t, abs(rotation-2*math.PI)<0.00001, "the requested mouse distance must rotate the gameplay camera through a complete turn")
				testing.expect(t, abs(menuui.cm360_from_sensitivity(factor,dpi)-cm)/cm<0.000001, "conversion must preserve both low and high sensitivity values")
				testing.expect(t, menuui.sensitivity_validate(factor,dpi)>0, "all supported physical sensitivities must stay usable")
			}
		}
		testing.expect(t, menuui.mouse_dpi_validate(0)==800 && menuui.mouse_dpi_validate(math.nan_f32())==800, "missing or invalid DPI must receive a usable manual default")
		testing.expect(t, menuui.sensitivity_validate(-1,800)==1 && menuui.sensitivity_validate(math.inf_f32(1),800)==1, "invalid camera multipliers must never reach gameplay")
	}
}
