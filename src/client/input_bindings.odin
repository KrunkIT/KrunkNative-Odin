package main

import "base:runtime"
import "core:math"
import glfw "vendor:glfw"
import menuui "../menu"
import shared "../shared"

// Both gameplay commands and freecam use this angular mouse delta. World FOV
// never affects cm/360; explicit ADS replaces the automatic zoom scaling.
client_mouse_rotation :: proc(client: ^Client, delta: shared.Vec2) -> shared.Vec2 {
	factor := client.sensitivity / max(1, client.camera.zoom)
	if client.advanced_sensitivity {
		aim: f32 = 0
		if client.me != nil && client.me.weapon != nil {
			aim = clamp(client.me.aim_val, 0, 1)
			// Use the same interpolated ADS state as the camera, including live play.
			if client.me.weapon.zoom > 1 {
				aim = clamp((client.camera.zoom-1)/(client.me.weapon.zoom-1), 0, 1)
			}
		}
		ads := menuui.ads_sensitivity_validate(client.ads_sensitivity, client.sensitivity, client.mouse_dpi)
		factor = math.lerp(client.sensitivity, ads, aim)
	}
	rotation := delta * (shared.GAME_CONSTANTS.mouse_sensitivity * factor)
	if client.invert_mouse { rotation.y = -rotation.y }
	return rotation
}

client_binding_key :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()
	if g_client != nil && g_client.menu.binding_capture != 0 && action == glfw.PRESS && g_client.binding_event == 0 { g_client.binding_event = key }
}

client_binding_mouse :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	context = runtime.default_context()
	if g_client != nil && g_client.menu.binding_capture != 0 && action == glfw.PRESS && g_client.binding_event == 0 { g_client.binding_event = -button-1 }
}

client_binding_down :: proc(window: glfw.WindowHandle, code: i32) -> bool {
	if code == 0 { return false }
	if code < 0 { return glfw.GetMouseButton(window, -code-1) == glfw.PRESS }
	return glfw.GetKey(window, code) == glfw.PRESS
}

client_action_down :: proc(client: ^Client, action: menuui.Binding_Action, read: proc(glfw.WindowHandle, i32) -> bool = client_binding_down) -> bool {
	pair := client.bindings[action]
	return read(client.window, pair[0]) || read(client.window, pair[1])
}

client_binding_used :: proc(client: ^Client, code: i32) -> bool {
	for pair in client.bindings { if pair[0] == code || pair[1] == code { return true } }
	return false
}

// Keep the input-to-command mapping shared by both slots; all three gameplay
// paths (practice, native networking and live networking) consume this command.
client_bound_input :: proc(held: [menuui.Binding_Action]bool, last_swap: ^u8) -> shared.Input {
	input := shared.Input{move_dir = -1, jump = held[.JUMP], crouch = held[.CROUCH], reload = held[.RELOAD], shoot = held[.FIRE], scope = held[.AIM]}
	if held[.SECONDARY] { input.swap = 1 }
	else if held[.MELEE] { input.swap = 2 }
	if input.swap == last_swap^ { input.swap = 0 }
	last_swap^ = held[.SECONDARY] ? 1 : held[.MELEE] ? 2 : 0
	forward, back, left, right := held[.FORWARD], held[.BACKWARD], held[.LEFT], held[.RIGHT]
	if forward != back {
		input.move_dir += forward ? 1 : 5
		if left != right { input.move_dir += right ? (forward ? 1 : -1) : (forward ? 7 : 1) }
	} else if left != right { input.move_dir += right ? 3 : 7 }
	return input
}
