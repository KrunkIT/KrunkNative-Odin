package main

import "core:fmt"
import "core:math"
import shared "../shared"

Class_Picker_Layout :: struct {
	start_x, start_y: f32,
	button_width, button_height: f32,
	columns: i32,
	gap: f32,
}

Settings_Layout :: struct {
	x, y, width, height: f32,
	scale: f32,
}

menu_scale_value :: proc(client: ^Client) -> f32 {
	return clamp(client.ui.height / 900.0, 0.75, 1.35)
}

class_picker_layout :: proc(client: ^Client) -> Class_Picker_Layout {
	scale := menu_scale_value(client)

	columns := i32(client.ui.width < 1050 ? 2 : 3)
	button_width := 250.0 * scale
	button_height := 48.0 * scale
	gap := 12.0 * scale

	class_count := shared.class_rotation_count()
	rows := (class_count + int(columns) - 1) / int(columns)

	total_width := f32(columns) * button_width + f32(columns - 1) * gap
	total_height := f32(rows) * button_height + f32(rows - 1) * gap

	return Class_Picker_Layout{
		start_x = (client.ui.width - total_width) * 0.5,
		start_y = client.ui.height * 0.2,
		button_width = button_width,
		button_height = button_height,
		columns = columns,
		gap = gap,
	}
}

class_button_rect :: proc(layout: Class_Picker_Layout, index: int) -> (x, y, width, height: f32) {
	col := i32(index) % layout.columns
	row := i32(index) / layout.columns

	x = layout.start_x + f32(col) * (layout.button_width + layout.gap)
	y = layout.start_y + f32(row) * (layout.button_height + layout.gap)

	return x, y, layout.button_width, layout.button_height
}

// pick_your_class_button_rect is the side button shown on the spawn screen.
pick_your_class_button_rect :: proc(client: ^Client) -> (x, y, width, height: f32) {
	scale := menu_scale_value(client)
	width = 190.0 * scale
	height = 52.0 * scale
	x = client.ui.width - width - 24.0 * scale
	y = (client.ui.height - height) * 0.5
	return
}

settings_button_rect :: proc(client: ^Client) -> (x, y, width, height: f32) {
	scale := menu_scale_value(client)
	width = 190.0 * scale
	height = 52.0 * scale
	x = 24.0 * scale
	y = (client.ui.height - height) * 0.5
	return
}

settings_layout :: proc(client: ^Client) -> Settings_Layout {
	scale := menu_scale_value(client)
	width := min(650.0 * scale, client.ui.width - 32.0 * scale)
	height := min(440.0 * scale, client.ui.height - 32.0 * scale)
	return Settings_Layout{
		x = (client.ui.width - width) * 0.5,
		y = (client.ui.height - height) * 0.5,
		width = width,
		height = height,
		scale = scale,
	}
}

settings_back_rect :: proc(layout: Settings_Layout) -> (x, y, width, height: f32) {
	width = 132.0 * layout.scale
	height = 44.0 * layout.scale
	x = layout.x + (layout.width - width) * 0.5
	y = layout.y + layout.height - height - 22.0 * layout.scale
	return
}

settings_mode_rect :: proc(layout: Settings_Layout, index: i32) -> (x, y, width, height: f32) {
	gap := 8.0 * layout.scale
	padding := 28.0 * layout.scale
	width = (layout.width - padding * 2.0 - gap * 2.0) / 3.0
	height = 44.0 * layout.scale
	x = layout.x + padding + f32(index) * (width + gap)
	y = layout.y + 105.0 * layout.scale
	return
}

settings_resolution_control_rect :: proc(layout: Settings_Layout) -> (x, y, width, height: f32) {
	width = 255.0 * layout.scale
	height = 44.0 * layout.scale
	x = layout.x + layout.width - width - 28.0 * layout.scale
	y = layout.y + 183.0 * layout.scale
	return
}

settings_sensitivity_track_rect :: proc(layout: Settings_Layout) -> (x, y, width, height: f32) {
	width = 330.0 * layout.scale
	height = 18.0 * layout.scale
	x = layout.x + layout.width - width - 28.0 * layout.scale
	y = layout.y + 275.0 * layout.scale
	return
}

// class_picker_back_rect is the BACK button on the class picker screen.
class_picker_back_rect :: proc(client: ^Client) -> (x, y, width, height: f32) {
	scale := menu_scale_value(client)
	width = 140.0 * scale
	height = 44.0 * scale
	x = (client.ui.width - width) * 0.5
	y = client.ui.height * 0.2 + f32((shared.class_rotation_count() + int(client.ui.width < 1050 ? 2 : 3) - 1) / int(client.ui.width < 1050 ? 2 : 3)) * (48.0 * scale + 12.0 * scale) + 30.0 * scale
	return
}

point_in_rect :: proc(px, py, rx, ry, rw, rh: f32) -> bool {
	return px >= rx && px < rx + rw && py >= ry && py < ry + rh
}

hud_render :: proc(client: ^Client, now: f32) {
	progress := math.mod(now, 1.6) / 0.8
	if progress > 1 {
		progress = 2 - progress
	}

	ui_fill_rect(client.ui, shared.Vec4{0.0, 0.0, 0.0, 0.5}, 0.0, 0.0, client.ui.width, client.ui.height)

	menu_scale := menu_scale_value(client)

	if client.class_picker_open {
		render_class_picker(client, menu_scale)
	} else if client.settings_open {
		render_settings(client)
	} else {
		render_spawn_screen(client, now, progress, menu_scale)
	}
}

render_spawn_screen :: proc(client: ^Client, now, progress, menu_scale: f32) {
	instructions := "CLICK TO PLAY"
	text_size := (32.0 - 2.0 * progress) * menu_scale
	opacity := 0.8 * (1.0 - 0.7 * progress)
	text_width := ui_measure_text(client.ui, instructions, text_size)

	ui_fill_text(client.ui, shared.Vec4{1.0, 1.0, 1.0, opacity}, instructions, (client.ui.width - text_width) * 0.5, client.ui.height * 0.5, text_size)

	// Side button to open the class picker.
	bx, by, bw, bh := pick_your_class_button_rect(client)
	ui_round_rect(client.ui, shared.Vec4{0.0, 0.0, 0.0, 0.55}, bx, by, bw, bh, 8.0 * menu_scale)

	label := "Pick Your Class"
	label_size := 18.0 * menu_scale
	label_width := ui_measure_text(client.ui, label, label_size)
	ui_fill_text(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.9}, label, bx + (bw - label_width) * 0.5, by + (bh + label_size) * 0.5 - 4.0 * menu_scale, label_size)

	// Matching side button for the settings menu.
	bx, by, bw, bh = settings_button_rect(client)
	ui_round_rect(client.ui, shared.Vec4{0.0, 0.0, 0.0, 0.55}, bx, by, bw, bh, 8.0 * menu_scale)

	label = "SETTINGS"
	label_width = ui_measure_text(client.ui, label, label_size)
	ui_fill_text(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.9}, label, bx + (bw - label_width) * 0.5, by + (bh + label_size) * 0.5 - 4.0 * menu_scale, label_size)

	current_class := fmt.tprintf("Class: %s", client.game.classes[client.selected_class].name) if client.selected_class >= 0 && client.selected_class < i32(len(client.game.classes)) else ""
	if len(current_class) > 0 {
		info_size := 16.0 * menu_scale
		info_width := ui_measure_text(client.ui, current_class, info_size)
		ui_fill_text(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.6}, current_class, (client.ui.width - info_width) * 0.5, client.ui.height * 0.5 + 40.0 * menu_scale, info_size)
	}
}

render_centered_button_label :: proc(client: ^Client, label: string, x, y, width, height, size: f32, color: shared.Vec4) {
	text_width := ui_measure_text(client.ui, label, size)
	ui_fill_text(client.ui, color, label, x + (width - text_width) * 0.5, y + (height + size) * 0.5 - 4.0 * menu_scale_value(client), size)
}

render_settings :: proc(client: ^Client) {
	layout := settings_layout(client)
	panel := shared.Vec4{0.035, 0.04, 0.05, 0.96}
	selected := shared.Vec4{0.16, 0.55, 0.28, 0.95}
	control := shared.Vec4{0.12, 0.13, 0.15, 1.0}
	white := shared.Vec4{1.0, 1.0, 1.0, 0.95}
	muted := shared.Vec4{1.0, 1.0, 1.0, 0.68}

	ui_round_rect(client.ui, panel, layout.x, layout.y, layout.width, layout.height, 8.0 * layout.scale)

	title := "SETTINGS"
	title_size := 30.0 * layout.scale
	title_width := ui_measure_text(client.ui, title, title_size)
	ui_fill_text(client.ui, white, title, layout.x + (layout.width - title_width) * 0.5, layout.y + 52.0 * layout.scale, title_size)

	label_size := 16.0 * layout.scale
	ui_fill_text(client.ui, muted, "DISPLAY MODE", layout.x + 28.0 * layout.scale, layout.y + 91.0 * layout.scale, label_size)

	mode_labels := [?]string{"WINDOWED", "BORDERLESS", "FULLSCREEN"}
	for i in 0 ..< 3 {
		x, y, w, h := settings_mode_rect(layout, i32(i))
		button_color := control
		if i32(client.display_mode) == i32(i) {
			button_color = selected
		}
		ui_round_rect(client.ui, button_color, x, y, w, h, 6.0 * layout.scale)
		render_centered_button_label(client, mode_labels[i], x, y, w, h, 15.0 * layout.scale, white)
	}

	row_label_y := layout.y + 212.0 * layout.scale
	ui_fill_text(client.ui, white, "RESOLUTION", layout.x + 28.0 * layout.scale, row_label_y, 18.0 * layout.scale)

	rx, ry, rw, rh := settings_resolution_control_rect(layout)
	arrow_width := 48.0 * layout.scale
	ui_round_rect(client.ui, control, rx, ry, rw, rh, 6.0 * layout.scale)
	ui_fill_rect(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.08}, rx + arrow_width, ry, 1.0, rh)
	ui_fill_rect(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.08}, rx + rw - arrow_width, ry, 1.0, rh)
	render_centered_button_label(client, "<", rx, ry, arrow_width, rh, 22.0 * layout.scale, white)
	render_centered_button_label(client, ">", rx + rw - arrow_width, ry, arrow_width, rh, 22.0 * layout.scale, white)
	resolution := DISPLAY_RESOLUTIONS[client.resolution_index]
	resolution_label := fmt.tprintf("%d x %d", resolution.width, resolution.height)
	render_centered_button_label(client, resolution_label, rx + arrow_width, ry, rw - arrow_width * 2.0, rh, 17.0 * layout.scale, white)

	ui_fill_text(client.ui, white, "SENSITIVITY", layout.x + 28.0 * layout.scale, layout.y + 292.0 * layout.scale, 18.0 * layout.scale)
	sensitivity_label := fmt.tprintf("%d%%", i32(math.round(client.sensitivity * 100.0)))
	value_width := ui_measure_text(client.ui, sensitivity_label, 17.0 * layout.scale)
	sx, sy, sw, sh := settings_sensitivity_track_rect(layout)
	ui_fill_text(client.ui, muted, sensitivity_label, sx + sw - value_width, sy - 13.0 * layout.scale, 17.0 * layout.scale)

	track_y := sy + (sh - 6.0 * layout.scale) * 0.5
	ui_round_rect(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.18}, sx, track_y, sw, 6.0 * layout.scale, 3.0 * layout.scale)
	progress := (client.sensitivity - 0.1) / 1.9
	fill_width := sw * progress
	ui_round_rect(client.ui, selected, sx, track_y, max(fill_width, 6.0 * layout.scale), 6.0 * layout.scale, 3.0 * layout.scale)
	knob_size := 18.0 * layout.scale
	ui_round_rect(client.ui, white, sx + fill_width - knob_size * 0.5, sy, knob_size, knob_size, knob_size * 0.5)

	bx, by, bw, bh := settings_back_rect(layout)
	ui_round_rect(client.ui, control, bx, by, bw, bh, 6.0 * layout.scale)
	render_centered_button_label(client, "BACK", bx, by, bw, bh, 18.0 * layout.scale, white)
}

settings_handle_click :: proc(client: ^Client, mouse_x, mouse_y: f32) -> bool {
	layout := settings_layout(client)

	bx, by, bw, bh := settings_back_rect(layout)
	if point_in_rect(mouse_x, mouse_y, bx, by, bw, bh) {
		client.settings_open = false
		return true
	}

	for i in 0 ..< 3 {
		x, y, w, h := settings_mode_rect(layout, i32(i))
		if point_in_rect(mouse_x, mouse_y, x, y, w, h) {
			client_set_display_mode(client, Display_Mode(i))
			return true
		}
	}

	rx, ry, rw, rh := settings_resolution_control_rect(layout)
	if point_in_rect(mouse_x, mouse_y, rx, ry, rw, rh) {
		if mouse_x < rx + rw * 0.5 {
			client.resolution_index = (client.resolution_index + i32(len(DISPLAY_RESOLUTIONS)) - 1) % i32(len(DISPLAY_RESOLUTIONS))
		} else {
			client.resolution_index = (client.resolution_index + 1) % i32(len(DISPLAY_RESOLUTIONS))
		}
		client_apply_display_settings(client)
		return true
	}

	sx, sy, sw, sh := settings_sensitivity_track_rect(layout)
	if point_in_rect(mouse_x, mouse_y, sx - 8.0 * layout.scale, sy - 12.0 * layout.scale, sw + 16.0 * layout.scale, sh + 24.0 * layout.scale) {
		progress := clamp((mouse_x - sx) / sw, 0.0, 1.0)
		client.sensitivity = math.round((0.1 + progress * 1.9) * 100.0) / 100.0
		return true
	}

	// The settings panel is modal; clicks outside controls must not start play.
	return true
}

render_class_picker :: proc(client: ^Client, menu_scale: f32) {
	title := "SELECT CLASS"
	title_size := 36.0 * menu_scale
	title_width := ui_measure_text(client.ui, title, title_size)
	ui_fill_text(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.9}, title, (client.ui.width - title_width) * 0.5, client.ui.height * 0.12, title_size)

	layout := class_picker_layout(client)
	selected_color := shared.Vec4{0.2, 0.6, 0.2, 0.9}
	normal_color := shared.Vec4{0.0, 0.0, 0.0, 0.55}
	text_color := shared.Vec4{1.0, 1.0, 1.0, 0.95}

	class_count := shared.class_rotation_count()

	for i in 0 ..< class_count {
		x, y, w, h := class_button_rect(layout, i)
		class_id := shared.class_rotation_id(i)

		if class_id == client.selected_class {
			ui_round_rect(client.ui, selected_color, x, y, w, h, 8.0 * menu_scale)
		} else {
			ui_round_rect(client.ui, normal_color, x, y, w, h, 8.0 * menu_scale)
		}

		name := shared.class_config_name(int(class_id))
		if class_id >= 0 && class_id < i32(len(client.game.classes)) {
			name = client.game.classes[class_id].name
		}
		text_size := 20.0 * menu_scale
		text_width := ui_measure_text(client.ui, name, text_size)
		ui_fill_text(client.ui, text_color, name, x + (w - text_width) * 0.5, y + (h + text_size) * 0.5 - 5.0 * menu_scale, text_size)
	}

	// Back button.
	bx, by, bw, bh := class_picker_back_rect(client)
	ui_round_rect(client.ui, shared.Vec4{0.0, 0.0, 0.0, 0.55}, bx, by, bw, bh, 8.0 * menu_scale)

	label := "BACK"
	label_size := 20.0 * menu_scale
	label_width := ui_measure_text(client.ui, label, label_size)
	ui_fill_text(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.9}, label, bx + (bw - label_width) * 0.5, by + (bh + label_size) * 0.5 - 4.0 * menu_scale, label_size)
}
