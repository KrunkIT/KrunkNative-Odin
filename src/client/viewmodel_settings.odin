package main

import "core:math"
import menuui "../menu"
import shared "../shared"

client_viewmodel_values :: proc(client: ^Client) -> menuui.Viewmodel_Settings {
	if client == nil { return menuui.DEFAULT_VIEWMODEL_SETTINGS }
	settings := client.viewmodel_settings
	if client.menu.settings_active && client.menu.page == .SETTINGS { settings = client.menu.settings_draft.viewmodel }
	return menuui.viewmodel_settings_validate(settings)
}

viewmodel_weapon_visible :: proc(weapon: ^shared.Weapon, settings: menuui.Viewmodel_Settings) -> bool {
	// Match the official weapon categories rather than loadout slots: some
	// classes carry melee in slot 0 or omit a secondary altogether.
	if weapon.melee { return settings.toggles[.SHOW_MELEE] }
	if weapon.secondary { return settings.toggles[.SHOW_SECONDARY] }
	return settings.toggles[.SHOW_PRIMARY]
}

client_aim_input :: proc(client: ^Client, down, enabled: bool) -> bool {
	if !enabled {
		client.aim_pressed, client.aim_toggled = down, false
		return false
	}
	settings := client_viewmodel_values(client)
	if !settings.toggles[.TOGGLE_ADS] {
		client.aim_pressed, client.aim_toggled = down, false
		return down
	}
	if down && !client.aim_pressed { client.aim_toggled = !client.aim_toggled }
	client.aim_pressed = down
	return client.aim_toggled
}

viewmodel_zoom :: proc(weapon_zoom, aim: f32, settings: menuui.Viewmodel_Settings) -> f32 {
	return 1 + (weapon_zoom-1) * clamp(aim, 0, 1) * settings.values[.ADS_FOV_POWER]
}

client_world_fov :: proc(client: ^Client) -> f32 {
	if client.menu.settings_active && client.menu.page == .SETTINGS { return menuui.fov_validate(client.menu.settings_draft.fov) * math.PI/180 }
	return client.camera.fov
}
