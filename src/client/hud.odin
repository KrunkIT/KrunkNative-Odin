package main

import "base:runtime"
import "core:fmt"
import "core:encoding/json"
import "core:math"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import menuui "../menu"
import clay "../third_party/clay"
import shared "../shared"

menu_measure_text :: proc "c" (label: clay.StringSlice, config: ^clay.TextElementConfig, user: rawptr) -> clay.Dimensions {
	context = runtime.default_context()
	ui := cast(^UI)user
	return {ui_measure_text(ui, string(label.chars[:label.length]), f32(config.fontSize)), f32(config.fontSize)}
}

menu_scroll :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
	if g_client != nil && !g_client.mouse_state.locked { g_client.menu_scroll += clay.Vector2{f32(x), f32(y)} }
}

menu_view :: proc(client: ^Client) -> menuui.View {
	classes := make([]menuui.Class, len(client.game.classes), context.temp_allocator)
	for class, i in client.game.classes {
		weapon_name := "No primary weapon"
		if len(class.loadout) > 0 {
			id := class.loadout[0]
			if id >= 0 && int(id) < len(client.game.weapons) && client.game.weapons[id] != nil { weapon_name = client.game.weapons[id].name }
		}
		classes[i] = {id = i32(i), name = class.name, weapon = weapon_name, health = class.health, speed = class.speed, wall_jump = class.wall_jump, available = shared.class_is_in_rotation(i32(i))}
	}
	map_name := "CURRENT MAP"
	if client.game.map_inst != nil {
		if root, ok := client.game.map_inst.raw_data.(json.Object); ok {
			if name, name_ok := root["name"].(json.String); name_ok { map_name = string(name) }
		}
		if map_name == "CURRENT MAP" {
			if len(g_map_name) > 0 { map_name = g_map_name }
			else if client.game.current_map_index >= 0 && int(client.game.current_map_index) < len(shared.ROTATION_MAPS) { map_name = shared.DEFAULT_MAP_NAMES[shared.ROTATION_MAPS[client.game.current_map_index]] }
		}
	}
	resolution := DISPLAY_RESOLUTIONS[client.resolution_index]
	player_count := 0
	for player in client.game.players { if player.active { player_count += 1 } }
	return {
		classes = classes, selected_class = client.selected_class,
		online = client.net.connected, active = client.me != nil && client.me.active,
		spawn_pending = client.spawn_pending, ready = client.game.ready && (!client.net.connected || client.net.match_state_received),
		map_name = map_name, mode = "HARDPOINT", player_count = player_count,
		display_mode = i32(client.display_mode), sensitivity = client.sensitivity, show_fps = client.show_fps,
		resolution = fmt.tprintf("%d x %d", resolution.width, resolution.height),
	}
}

menu_apply_action :: proc(client: ^Client, action: menuui.Action) {
	switch action.kind {
	case .NONE:
	case .PLAY:
		if !client.game.ready || client.spawn_pending || client.net.connected && !client.net.match_state_received { return }
		glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
		client.mouse_state.locked = true
		x, y := glfw.GetCursorPos(client.window)
		client.mouse_state.last_pos = {f32(x), f32(y)}
	case .QUIT:
		glfw.SetWindowShouldClose(client.window, true)
	case .SELECT_CLASS:
		if shared.class_is_in_rotation(action.index) { client.selected_class = action.index }
	case .DISPLAY_MODE:
		client_set_display_mode(client, Display_Mode(action.index))
	case .RESOLUTION:
		client.resolution_index = (client.resolution_index + action.index + i32(len(DISPLAY_RESOLUTIONS))) % i32(len(DISPLAY_RESOLUTIONS))
		client_apply_display_settings(client)
	case .SENSITIVITY:
		client.sensitivity = math.round(action.value * 100) / 100
	case .FPS:
		client.show_fps = !client.show_fps
	}
}

menu_color :: proc(color: clay.Color) -> shared.Vec4 { return {color[0] / 255, color[1] / 255, color[2] / 255, color[3] / 255} }

menu_scissor :: proc(ui: ^UI, box: clay.BoundingBox) {
	gl.Scissor(i32(box.x), i32(ui.height - box.y - box.height), i32(box.width), i32(box.height))
}

menu_render_commands :: proc(ui: ^UI, commands: clay.ClayArray(clay.RenderCommand)) {
	clips: [32]clay.BoundingBox
	clip_count := 0
	for command in commands.internalArray[:commands.length] {
		box := command.boundingBox
		switch command.commandType {
		case .Rectangle:
			data := command.renderData.rectangle
			if box.width > 0 && box.height > 0 { ui_round_rect(ui, menu_color(data.backgroundColor), box.x, box.y, box.width, box.height, data.cornerRadius.topLeft) }
		case .Text:
			data := command.renderData.text
			// Existing text drawing takes a baseline; Clay supplies a text box.
			ascent, descent, gap: i32
			stb_font_metrics(&ascent, &descent, &gap)
			baseline := box.y + f32(data.fontSize) * f32(ascent) / f32(ascent - descent) + max(0, (box.height - f32(data.fontSize)) * 0.5)
			ui_fill_text(ui, menu_color(data.textColor), string(data.stringContents.chars[:data.stringContents.length]), box.x, baseline, f32(data.fontSize))
		case .Border:
			data := command.renderData.border
			color := menu_color(data.color)
			if data.width.left > 0 { ui_fill_rect(ui, color, box.x, box.y, f32(data.width.left), box.height) }
			if data.width.right > 0 { ui_fill_rect(ui, color, box.x + box.width - f32(data.width.right), box.y, f32(data.width.right), box.height) }
			if data.width.top > 0 { ui_fill_rect(ui, color, box.x, box.y, box.width, f32(data.width.top)) }
			if data.width.bottom > 0 { ui_fill_rect(ui, color, box.x, box.y + box.height - f32(data.width.bottom), box.width, f32(data.width.bottom)) }
		case .ScissorStart:
			assert(clip_count < len(clips))
			if clip_count > 0 {
				parent := clips[clip_count - 1]
				right := min(box.x + box.width, parent.x + parent.width)
				bottom := min(box.y + box.height, parent.y + parent.height)
				box.x = max(box.x, parent.x); box.y = max(box.y, parent.y)
				box.width = max(0, right - box.x); box.height = max(0, bottom - box.y)
			}
			clips[clip_count] = box
			clip_count += 1
			gl.Enable(gl.SCISSOR_TEST)
			menu_scissor(ui, box)
		case .ScissorEnd:
			clip_count = max(0, clip_count - 1)
			if clip_count == 0 { gl.Disable(gl.SCISSOR_TEST) }
			else { menu_scissor(ui, clips[clip_count - 1]) }
		case .None, .Image, .Custom, .OverlayColorStart, .OverlayColorEnd:
			// This prototype declares rectangles, borders, text and clips.
		}
	}
	gl.Disable(gl.SCISSOR_TEST)
}

hud_render :: proc(client: ^Client, delta: f32) {
	width, height := glfw.GetWindowSize(client.window)
	x, y := glfw.GetCursorPos(client.window)
	input := menuui.Input{
		pointer = {f32(x) * client.ui.width / f32(max(width, 1)), f32(y) * client.ui.height / f32(max(height, 1))},
		down = glfw.GetMouseButton(client.window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS,
		tab = glfw.GetKey(client.window, glfw.KEY_TAB) == glfw.PRESS,
		shift = glfw.GetKey(client.window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS,
		enter = glfw.GetKey(client.window, glfw.KEY_ENTER) == glfw.PRESS,
		escape = glfw.GetKey(client.window, glfw.KEY_ESCAPE) == glfw.PRESS,
		left = glfw.GetKey(client.window, glfw.KEY_LEFT) == glfw.PRESS,
		right = glfw.GetKey(client.window, glfw.KEY_RIGHT) == glfw.PRESS,
		scroll = client.menu_scroll,
	}
	client.menu_scroll = {}
	view := menu_view(client)
	commands := menuui.build(&client.menu, view, input, client.ui.width, client.ui.height, delta)
	ui_fill_rect(client.ui, {0.015, 0.025, 0.035, 0.55}, 0, 0, client.ui.width, client.ui.height)
	menu_render_commands(client.ui, commands)
	action := menuui.interact(&client.menu, input, view)
	menu_apply_action(client, action)
}
