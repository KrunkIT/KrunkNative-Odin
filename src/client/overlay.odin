package main

import "core:fmt"
import shared "../shared"

ammo_icon: u32
timer_icon: u32
health_icon: u32
class_icons: map[i32]u32

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

		segment_color := shared.hex_to_vec(0x9eeb56)

		for i in 0 ..< class.health_segments {
			ui_round_rect(
				client.ui, background_color,
				anchor.x + (113.0 + 50.0 * f32(i)) * client.ui.scale,
				anchor.y - 50.0 * client.ui.scale,
				40.0 * client.ui.scale,
				50.0 * client.ui.scale,
				5.0 * client.ui.scale,
			)

			health_per_segment := f32(client.me.max_health) / f32(class.health_segments)
			progress := clamp((client.me.health - f32(i) * health_per_segment) / health_per_segment, 0.0, 1.0)

			for j in 0 ..< 2 {
				ui_round_rect(
					client.ui, segment_color,
					anchor.x + (113.0 + 50.0 * f32(i)) * client.ui.scale,
					anchor.y - 50.0 * client.ui.scale,
					40.0 * client.ui.scale * progress,
					(50.0 - 10.0 * f32(j)) * client.ui.scale,
					5.0 * client.ui.scale,
				)

				ui_round_rect(
					client.ui, background_color,
					anchor.x + (113.0 + 50.0 * f32(i)) * client.ui.scale,
					anchor.y - 50.0 * client.ui.scale,
					40.0 * client.ui.scale * progress,
					50.0 * client.ui.scale * (1.0 - f32(j)),
					5.0 * client.ui.scale,
				)
			}
		}

		health_str := fmt.tprintf("%.f", client.me.health)
		max_health_str := fmt.tprintf("| %d", client.me.max_health)

		health_size := 20.0 * client.ui.scale
		health_str_width := ui_measure_text(client.ui, health_str, health_size)
		space_width := ui_measure_text(client.ui, " ", health_size)

		text_width := health_str_width + space_width + ui_measure_text(client.ui, max_health_str, health_size)

		ui_round_rect(client.ui, background_color, anchor.x + 113.0 * client.ui.scale, anchor.y - (59.0 + 41.0) * client.ui.scale, text_width + 54.0 * client.ui.scale, 41.0 * client.ui.scale, 5.0 * client.ui.scale)
		ui_fill_text(client.ui, white, health_str, anchor.x + 125.0 * client.ui.scale, anchor.y - (59.0 + 8.0) * client.ui.scale, health_size)
		ui_fill_text(client.ui, white, " ", anchor.x + 125.0 * client.ui.scale + health_str_width, anchor.y - (59.0 + 8.0) * client.ui.scale, health_size)
		ui_fill_text(client.ui, max_health_color, max_health_str, anchor.x + 125.0 * client.ui.scale + health_str_width + space_width, anchor.y - (59.0 + 8.0) * client.ui.scale, health_size)

		if health_icon == 0 {
			icon_path := shared.concat(shared.assets_path(), "img/hp_0.png")
			health_icon = load_texture(icon_path)
			delete(icon_path)
		}

		if health_icon != 0 {
			ui_draw_image(client.ui, health_icon, anchor.x + 130.0 * client.ui.scale + text_width, anchor.y - (59.0 + 41.0) * client.ui.scale + (41.0 - 28.0) * 0.5 * client.ui.scale, 28.0 * client.ui.scale, 28.0 * client.ui.scale)
		}
	}

	// test crosshair
	{
		color := shared.Vec4{1.0, 1.0, 0.0, 1.0}

		ui_fill_rect(client.ui, color, client.ui.width * 0.5 - 1.0 * client.ui.scale, client.ui.height * 0.5 - 5.0 * client.ui.scale, 2.0 * client.ui.scale, 10.0 * client.ui.scale)
		ui_fill_rect(client.ui, color, client.ui.width * 0.5 - 5.0 * client.ui.scale, client.ui.height * 0.5 - 1.0 * client.ui.scale, 10.0 * client.ui.scale, 2.0 * client.ui.scale)
	}

	// bottom right HUD (ammo)
	{
		max_ammo_color := shared.Vec4{1.0, 1.0, 1.0, 0.7}
		anchor := shared.Vec2{client.ui.width - 20.0 * client.ui.scale, client.ui.height - 35.0 * client.ui.scale}

		if ammo_icon == 0 {
			icon_path := shared.concat(shared.assets_path(), "textures/ammo_0.png")

			ammo_icon = load_texture(icon_path)
			delete(icon_path)
		}

		if ammo_icon != 0 && client.me != nil && client.me.weapon != nil && client.me.loadout_index >= 0 && client.me.loadout_index < i32(len(client.me.ammo)) {
			ammo := client.me.ammo[client.me.loadout_index]
			ammo_str := fmt.tprintf("%d", ammo)

			max_ammo_str := "| -" if (client.game.mode != nil && client.game.mode.config.ammo_limit != 0) || client.me.weapon.ammo == 0 else fmt.tprintf("| %d", client.me.weapon.ammo)

			ammo_size := 35.0 * client.ui.scale
			ammo_str_width := ui_measure_text(client.ui, ammo_str, ammo_size)
			space_width := ui_measure_text(client.ui, " ", ammo_size)

			text_width := ammo_str_width + space_width + ui_measure_text(client.ui, max_ammo_str, ammo_size)
			ammo_holder_size := shared.Vec2{text_width + 107.0 * client.ui.scale, (65.0 + 7.0 + 8.0) * client.ui.scale}

			reload_animation: f32 = 0
			if client.me.weapon.reload_time != 0 {
				reload_animation = client.me.reload_timer / (client.me.weapon.reload_time * client.game.config.reload_speed)
			}

			ui_round_rect(client.ui, background_color, anchor.x - ammo_holder_size.x, anchor.y - ammo_holder_size.y, ammo_holder_size.x, ammo_holder_size.y, 10.0 * client.ui.scale)

			if reload_animation != 0 {
				reload_color := shared.Vec4{1.0, 1.0, 1.0, 0.247}
				ui_fill_rect_rclip(client.ui, reload_color, anchor.x - ammo_holder_size.x, anchor.y - ammo_holder_size.y, ammo_holder_size.x, ammo_holder_size.y, 10.0 * client.ui.scale, 1.0 - reload_animation)
			}

			ui_fill_text(client.ui, white, ammo_str, anchor.x - ammo_holder_size.x + 20.0 * client.ui.scale, anchor.y - ammo_holder_size.y * 0.5 + (35.0 - 14.0) * client.ui.scale, ammo_size)
			ui_fill_text(client.ui, white, " ", anchor.x - ammo_holder_size.x + ammo_str_width + 20.0 * client.ui.scale, anchor.y - ammo_holder_size.y * 0.5 + (35.0 - 14.0) * client.ui.scale, ammo_size)
			ui_fill_text(client.ui, max_ammo_color, max_ammo_str, anchor.x - ammo_holder_size.x + ammo_str_width + space_width + 20.0 * client.ui.scale, anchor.y - ammo_holder_size.y * 0.5 + (35.0 - 14.0) * client.ui.scale, ammo_size)

			ui_draw_image(client.ui, ammo_icon, anchor.x - ammo_holder_size.x + text_width + 35.0 * client.ui.scale, anchor.y - (55.0 + 7.0) * client.ui.scale, 55.0 * client.ui.scale, 55.0 * client.ui.scale)
		}
	}

	// top left HUD (timer)
	{
		top: f32 = client.show_fps ? 68.0 : 20.0
		anchor := shared.Vec2{20.0 * client.ui.scale, top * client.ui.scale}

		if timer_icon == 0 {
			icon_path := shared.concat(shared.assets_path(), "img/timer.png")

			timer_icon = load_texture(icon_path)
			delete(icon_path)
		}

		if timer_icon != 0 {
			remaining := max(0, int(client.game.match.time_remaining + 0.999))
			timer := fmt.tprintf("%02d:%02d", remaining / 60, remaining % 60)
			timer_width := ui_measure_text(client.ui, timer, 32.0 * client.ui.scale)

			ui_round_rect(client.ui, background_color, anchor.x, anchor.y, timer_width + 88.0 * client.ui.scale, 76.0 * client.ui.scale, 10.0 * client.ui.scale)
			ui_draw_image(client.ui, timer_icon, anchor.x + 10.0 * client.ui.scale, anchor.y + (76.0 - 45.0) * 0.5 * client.ui.scale, 45.0 * client.ui.scale, 45.0 * client.ui.scale)
			ui_fill_text(client.ui, white, timer, anchor.x + 68.0 * client.ui.scale, anchor.y + (76.0 - 18.0) * client.ui.scale, 32.0 * client.ui.scale)
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
		text_size := 24.0 * client.ui.scale
		sub_size := 15.0 * client.ui.scale
		width := max(ui_measure_text(client.ui, score, text_size), ui_measure_text(client.ui, rotation, sub_size)) + 50.0 * client.ui.scale
		x := (client.ui.width - width) * 0.5
		y := 20.0 * client.ui.scale
		ui_round_rect(client.ui, background_color, x, y, width, 72.0 * client.ui.scale, 8.0 * client.ui.scale)
		ui_fill_text(client.ui, white, score, x + (width - ui_measure_text(client.ui, score, text_size)) * 0.5, y + 31.0 * client.ui.scale, text_size)
		ui_fill_text(client.ui, status_color, rotation, x + (width - ui_measure_text(client.ui, rotation, sub_size)) * 0.5, y + 57.0 * client.ui.scale, sub_size)
	}
}

overlay_fini :: proc() {
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
