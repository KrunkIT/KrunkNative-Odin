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

menu_scale_value :: proc(client: ^Client) -> f32 {
	return clamp(client.ui.height / 900.0, 0.75, 1.35)
}

class_picker_layout :: proc(client: ^Client) -> Class_Picker_Layout {
	scale := menu_scale_value(client)

	columns := i32(client.ui.width < 1050 ? 2 : 3)
	button_width := 250.0 * scale
	button_height := 48.0 * scale
	gap := 12.0 * scale

	class_count := shared.class_config_name_count()
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

// class_picker_back_rect is the BACK button on the class picker screen.
class_picker_back_rect :: proc(client: ^Client) -> (x, y, width, height: f32) {
	scale := menu_scale_value(client)
	width = 140.0 * scale
	height = 44.0 * scale
	x = (client.ui.width - width) * 0.5
	y = client.ui.height * 0.2 + f32((shared.class_config_name_count() + int(client.ui.width < 1050 ? 2 : 3) - 1) / int(client.ui.width < 1050 ? 2 : 3)) * (48.0 * scale + 12.0 * scale) + 30.0 * scale
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

	current_class := fmt.tprintf("Class: %s", client.game.classes[client.selected_class].name) if client.selected_class >= 0 && client.selected_class < i32(len(client.game.classes)) else ""
	if len(current_class) > 0 {
		info_size := 16.0 * menu_scale
		info_width := ui_measure_text(client.ui, current_class, info_size)
		ui_fill_text(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.6}, current_class, (client.ui.width - info_width) * 0.5, client.ui.height * 0.5 + 40.0 * menu_scale, info_size)
	}
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

	class_count := shared.class_config_name_count()

	for i in 0 ..< class_count {
		x, y, w, h := class_button_rect(layout, i)

		if i32(i) == client.selected_class {
			ui_round_rect(client.ui, selected_color, x, y, w, h, 8.0 * menu_scale)
		} else {
			ui_round_rect(client.ui, normal_color, x, y, w, h, 8.0 * menu_scale)
		}

		name := shared.class_config_name(i)
		if i < len(client.game.classes) {
			name = client.game.classes[i].name
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
