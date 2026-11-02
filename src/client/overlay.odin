package main

import "core:fmt"
import gl "vendor:OpenGL"
import shared "../shared"

ammo_icon: u32
timer_icon: u32
health_icon: u32
class_icons: map[i32]u32
weapon_icons: map[i32]u32

HUD_TIMER_TEXT_SIZE :: 40.0
HUD_TIMER_ICON_SIZE :: 32.0
HUD_TIMER_TEXT_INSET :: 54.0
HUD_TIMER_RIGHT_PADDING :: 20.0

// Center the visible numerals within a HUD row using the active font's metrics.
overlay_numeric_baseline :: proc(top, height, text_size: f32) -> f32 {
	text_height := text_size * 0.5
	if glyph := load_glyph('0'); glyph != nil {
		text_height = glyph.h_bearing.y * text_size / 100.0
	}
	return top + (height + text_height) * 0.5
}

overlay_loadout_render :: proc(client: ^Client, right, bottom: f32) {
	if client.me == nil { return }
	if weapon_icons == nil { weapon_icons = make(map[i32]u32) }
	s := client.ui.scale
	row_height := 58.0 * s
	row: f32 = 0
	for weapon_id, slot in client.me.loadout {
		if weapon_id < 0 || int(weapon_id) >= len(client.game.weapons) { continue }
		weapon := client.game.weapons[weapon_id]
		if weapon == nil { continue }
		icon, cached := weapon_icons[weapon_id]
		if !cached {
			folder := "melee" if weapon.melee else "weapons"
			path := shared.concat(shared.assets_path(), fmt.tprintf("textures/%s/%s.png", folder, weapon.icon))
			icon = load_texture(path)
			delete(path)
			weapon_icons[weapon_id] = icon
			if icon != 0 {
				gl.BindTexture(gl.TEXTURE_2D, icon)
				gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
				gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
				g_active_texture = 0
			}
		}
		active := i32(slot) == client.me.loadout_index
		color := shared.Vec4{1, 1, 1, 1} if active else shared.Vec4{0.8, 0.8, 0.8, 0.6}
		top := bottom - f32(len(client.me.loadout)) * row_height + row * row_height
		// The bundled silhouettes use a 2:1 canvas, including their transparent padding.
		if icon != 0 {
			icon_top := top + (12.0 if weapon.melee else -8.0) * s
			ui_draw_image(client.ui, icon, right - 184.0 * s, icon_top, 160.0 * s, 80.0 * s, color)
		} else {
			text_size := 24.0 * s
			width := ui_measure_text(client.ui, weapon.name, text_size)
			ui_fill_text(client.ui, color, weapon.name, right - 28.0 * s - width, overlay_numeric_baseline(top, row_height, text_size), text_size)
		}
		// Match the actual swap keys rather than displaying unbound slot numbers.
		key := "[Q]" if weapon.melee else ("[E]" if weapon.secondary else "")
		if len(key) > 0 {
			key_size := 26.0 * s
			ui_fill_text(client.ui, color, key, right - ui_measure_text(client.ui, key, key_size), overlay_numeric_baseline(top, row_height, key_size), key_size)
		}
		row += 1
	}
}

overlay_ammo_render :: proc(client: ^Client) {
	if client.me == nil || client.me.weapon == nil { return }
	s := client.ui.scale
	right := client.ui.width - 20.0 * s
	bottom := client.ui.height - 35.0 * s
	height := 80.0 * s
	top := bottom - height
	overlay_loadout_render(client, right, top - 12.0 * s)
	if client.me.loadout_index < 0 || int(client.me.loadout_index) >= len(client.me.ammo) { return }

	if ammo_icon == 0 {
		path := shared.concat(shared.assets_path(), "textures/ammo_0.png")
		ammo_icon = load_texture(path)
		delete(path)
		if ammo_icon != 0 {
			gl.BindTexture(gl.TEXTURE_2D, ammo_icon)
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
			g_active_texture = 0
		}
	}

	weapon := client.me.weapon
	ammo_str := fmt.tprintf("%d", client.me.ammo[client.me.loadout_index])
	if weapon.melee || weapon.ammo == 0 { ammo_str = "-" }
	unlimited := weapon.ammo == 0 || (client.game.mode != nil && client.game.mode.config.ammo_limit != 0)
	max_ammo_str := "-" if unlimited else fmt.tprintf("%d", weapon.ammo)
	text_size := 80.0 * s
	ammo_width := ui_measure_text(client.ui, ammo_str, text_size)
	max_width := ui_measure_text(client.ui, max_ammo_str, text_size)
	width := ammo_width + max_width + 120.0 * s
	left := right - width
	baseline := overlay_numeric_baseline(top, height, text_size)
	white := shared.Vec4{1, 1, 1, 1}
	muted := shared.Vec4{0.7, 0.68, 0.66, 1}
	gold := shared.hex_to_vec(0xffd447)

	ui_round_rect(client.ui, shared.Vec4{0.04, 0.035, 0.025, 0.65}, left, top, width, height, 6.0 * s)
	if weapon.reload_time > 0 && client.game.config.reload_speed > 0 && client.me.reload_timer > 0 {
		progress := clamp(1.0 - client.me.reload_timer / (weapon.reload_time * client.game.config.reload_speed), 0.0, 1.0)
		ui_fill_rect_rclip(client.ui, shared.Vec4{1, 0.83, 0.28, 0.14}, left, top, width, height, 6.0 * s, 1.0 - progress)
	}
	ui_stroke_round_rect(client.ui, gold, left, top, width, height, 6.0 * s, 2.0 * s)
	ui_fill_text(client.ui, white, ammo_str, left + 18.0 * s, baseline, text_size)
	separator_x := left + 18.0 * s + ammo_width + 10.0 * s
	ui_fill_rect(client.ui, muted, separator_x, top + 16.0 * s, 3.0 * s, 48.0 * s)
	ui_fill_text(client.ui, muted, max_ammo_str, separator_x + 13.0 * s, baseline, text_size)
	if ammo_icon != 0 {
		ui_draw_image(client.ui, ammo_icon, right - 66.0 * s, top + 18.0 * s, 54.0 * s, 54.0 * s)
	}
}

overlay_render :: proc(client: ^Client, delta: f32) {
	white := shared.Vec4{1.0, 1.0, 1.0, 1.0}
	background_color := shared.Vec4{0.0, 0.0, 0.0, 0.4}

	// xp bar
	{
		anchor := shared.Vec2{20.0 * client.ui.scale, client.ui.height - 22.0 * client.ui.scale}

		ui_round_rect(client.ui, background_color, anchor.x, anchor.y, client.ui.width - 35.0 * client.ui.scale, 12.0 * client.ui.scale, 4.0 * client.ui.scale)
	}

	// bottom left HUD (class icon, health)
	if client.me != nil && client.me.class_index >= 0 && client.me.class_index < i32(len(client.game.classes)) {
		class := &client.game.classes[client.me.class_index]
		max_health_color := shared.Vec4{1.0, 1.0, 1.0, 0.8}

		anchor := shared.Vec2{20.0 * client.ui.scale, client.ui.height - 35.0 * client.ui.scale}
		class_icon_pos := shared.Vec2{anchor.x, anchor.y - 103.0 * client.ui.scale}

		ui_round_rect(client.ui, background_color, class_icon_pos.x, class_icon_pos.y, 103.0 * client.ui.scale, 103.0 * client.ui.scale, 10.0 * client.ui.scale)

		if class_icons == nil {
			class_icons = make(map[i32]u32)
		}

		class_icon := class_icons[class.icon_index]
		if class_icon == 0 {
			class_icon_path := shared.concat(shared.assets_path(), fmt.tprintf("textures/classes/icon_%d.png", class.icon_index))
			class_icon = load_texture(class_icon_path)
			delete(class_icon_path)
			class_icons[class.icon_index] = class_icon
		}

		if class_icon != 0 {
			ui_draw_image_rounded(client.ui, class_icon, class_icon_pos.x, class_icon_pos.y, 103.0 * client.ui.scale, 103.0 * client.ui.scale, 10.0 * client.ui.scale)
		}

		health_color := shared.hex_to_vec(0x9eeb56)
		bar_x := anchor.x + 113.0 * client.ui.scale
		bar_y := anchor.y - 50.0 * client.ui.scale
		bar_width := (50.0 * f32(max(1, class.health_segments)) - 10.0) * client.ui.scale
		bar_height := 50.0 * client.ui.scale
		progress: f32 = 0
		if client.me.max_health > 0 {
			progress = clamp(client.me.health / f32(client.me.max_health), 0.0, 1.0)
		}

		ui_round_rect(client.ui, background_color, bar_x, bar_y, bar_width, bar_height, 5.0 * client.ui.scale)
		if progress > 0 {
			fill_width := bar_width * progress
			ui_round_rect(client.ui, health_color, bar_x, bar_y, fill_width, bar_height, 5.0 * client.ui.scale)
			ui_round_rect(client.ui, background_color, bar_x, bar_y, fill_width, bar_height, 5.0 * client.ui.scale)
			ui_round_rect(client.ui, health_color, bar_x, bar_y, fill_width, 40.0 * client.ui.scale, 5.0 * client.ui.scale)
		}

		health_str := fmt.tprintf("%.f", client.me.health)
		max_health_str := fmt.tprintf("| %d", client.me.max_health)

		health_size := 40.0 * client.ui.scale
		health_str_width := ui_measure_text(client.ui, health_str, health_size)
		space_width := ui_measure_text(client.ui, " ", health_size)

		text_width := health_str_width + space_width + ui_measure_text(client.ui, max_health_str, health_size)

		health_top := anchor.y - 100.0 * client.ui.scale
		health_baseline := overlay_numeric_baseline(health_top, 41.0 * client.ui.scale, health_size)
		ui_round_rect(client.ui, background_color, anchor.x + 113.0 * client.ui.scale, health_top, text_width + 58.0 * client.ui.scale, 41.0 * client.ui.scale, 5.0 * client.ui.scale)
		ui_fill_text(client.ui, white, health_str, anchor.x + 125.0 * client.ui.scale, health_baseline, health_size)
		ui_fill_text(client.ui, max_health_color, max_health_str, anchor.x + 125.0 * client.ui.scale + health_str_width + space_width, health_baseline, health_size)

		if health_icon == 0 {
			icon_path := shared.concat(shared.assets_path(), "img/hp_0.png")
			health_icon = load_texture(icon_path)
			delete(icon_path)
		}

		if health_icon != 0 {
			ui_draw_image(client.ui, health_icon, anchor.x + 135.0 * client.ui.scale + text_width, health_top + (41.0 - 24.0) * 0.5 * client.ui.scale, 24.0 * client.ui.scale, 24.0 * client.ui.scale)
		}
	}

	// test crosshair
	{
		color := shared.Vec4{1.0, 1.0, 0.0, 1.0}

		ui_fill_rect(client.ui, color, client.ui.width * 0.5 - 1.0 * client.ui.scale, client.ui.height * 0.5 - 5.0 * client.ui.scale, 2.0 * client.ui.scale, 10.0 * client.ui.scale)
		ui_fill_rect(client.ui, color, client.ui.width * 0.5 - 5.0 * client.ui.scale, client.ui.height * 0.5 - 1.0 * client.ui.scale, 10.0 * client.ui.scale, 2.0 * client.ui.scale)
	}

	// Bottom right HUD: current loadout and ammo.
	overlay_ammo_render(client)

	// top left HUD (timer)
	{
		anchor := shared.Vec2{20.0 * client.ui.scale, 20.0 * client.ui.scale}

		if timer_icon == 0 {
			icon_path := shared.concat(shared.assets_path(), "img/timer.png")

			timer_icon = load_texture(icon_path)
			delete(icon_path)
		}

		if timer_icon != 0 {
			remaining := max(0, int(client.game.match.time_remaining + 0.999))
			timer := fmt.tprintf("%02d:%02d", remaining / 60, remaining % 60)
			timer_width := ui_measure_text(client.ui, timer, HUD_TIMER_TEXT_SIZE * client.ui.scale)
			baseline := overlay_numeric_baseline(anchor.y, 76.0 * client.ui.scale, HUD_TIMER_TEXT_SIZE * client.ui.scale)

			ui_round_rect(client.ui, background_color, anchor.x, anchor.y, timer_width + (HUD_TIMER_TEXT_INSET + HUD_TIMER_RIGHT_PADDING) * client.ui.scale, 76.0 * client.ui.scale, 10.0 * client.ui.scale)
			ui_draw_image(client.ui, timer_icon, anchor.x + 10.0 * client.ui.scale, anchor.y + (76.0 - HUD_TIMER_ICON_SIZE) * 0.5 * client.ui.scale, HUD_TIMER_ICON_SIZE * client.ui.scale, HUD_TIMER_ICON_SIZE * client.ui.scale)
			ui_fill_text(client.ui, white, timer, anchor.x + HUD_TIMER_TEXT_INSET * client.ui.scale, baseline, HUD_TIMER_TEXT_SIZE * client.ui.scale)
		}
	}

	// top-center objective scoreboard
	if client.game.match.objective.active_zone >= 0 {
		state := &client.game.match.objective
		zone_name := fmt.tprintf("POINT %c", rune('A' + state.active_zone))
		status := "NEUTRAL"
		status_color := shared.Vec4{0.85, 0.88, 0.9, 1.0}
		if state.contested {
			status = "CONTESTED"
			status_color = shared.Vec4{1.0, 0.72, 0.15, 1.0}
		} else if state.owner_team == 1 {
			status = client.game.config.team1_name
			status_color = shared.Vec4{0.25, 0.55, 1.0, 1.0}
		} else if state.owner_team == 2 {
			status = client.game.config.team2_name
			status_color = shared.Vec4{1.0, 0.3, 0.3, 1.0}
		}

		score := fmt.tprintf("%d   %s   %d", client.game.match.team_scores[1], zone_name, client.game.match.team_scores[2])
		rotation := fmt.tprintf("%s  |  rotates in %.0fs", status, state.rotation_remaining)
		text_size := 30.0 * client.ui.scale
		sub_size := 18.75 * client.ui.scale
		width := max(ui_measure_text(client.ui, score, text_size), ui_measure_text(client.ui, rotation, sub_size)) + 50.0 * client.ui.scale
		x := (client.ui.width - width) * 0.5
		y := 20.0 * client.ui.scale
		ui_round_rect(client.ui, background_color, x, y, width, 72.0 * client.ui.scale, 8.0 * client.ui.scale)
		ui_fill_text(client.ui, white, score, x + (width - ui_measure_text(client.ui, score, text_size)) * 0.5, y + 31.0 * client.ui.scale, text_size)
		ui_fill_text(client.ui, status_color, rotation, x + (width - ui_measure_text(client.ui, rotation, sub_size)) * 0.5, y + 57.0 * client.ui.scale, sub_size)
	}
}

overlay_fini :: proc() {
	for _, icon in weapon_icons {
		texture_release(icon)
	}
	delete(weapon_icons)
	weapon_icons = nil

	for _, icon in class_icons {
		texture_release(icon)
	}
	delete(class_icons)
	class_icons = nil

	texture_release(health_icon)
	texture_release(ammo_icon)
	texture_release(timer_icon)
	health_icon = 0
	ammo_icon = 0
	timer_icon = 0
}
