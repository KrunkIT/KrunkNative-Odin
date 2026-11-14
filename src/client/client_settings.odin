package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import menuui "../menu"

CLIENT_SETTINGS_PATH :: "client-settings.json"
Client_Settings :: struct {
	version: i32,
	display_mode, resolution_index, monitor_index: i32,
	sensitivity, mouse_dpi: f32,
	ads_sensitivity: f32,
	advanced_sensitivity, invert_mouse: bool,
	fov: f32,
	show_fps, vsync: bool,
	bindings: menuui.Bindings,
	hud: menuui.HUD_Settings,
	visuals: menuui.Visual_Settings,
	quality: menuui.Quality_Settings,
	viewmodel: menuui.Viewmodel_Settings,
	trails: menuui.Trail_Settings,
	crosshair: menuui.Crosshair_Settings,
}

client_settings_defaults :: proc() -> Client_Settings {
	return {version = 1, fov = menuui.DEFAULT_FOV, sensitivity = 1, ads_sensitivity = 1, mouse_dpi = menuui.DEFAULT_MOUSE_DPI, bindings = menuui.default_bindings(), visuals = menuui.DEFAULT_VISUAL_SETTINGS, viewmodel = menuui.DEFAULT_VIEWMODEL_SETTINGS, crosshair = menuui.DEFAULT_CROSSHAIR_SETTINGS}
}

client_settings_validate :: proc(settings: Client_Settings) -> Client_Settings {
	result := settings
	result.fov = menuui.fov_validate(result.fov)
	result.mouse_dpi = menuui.mouse_dpi_validate(result.mouse_dpi)
	result.sensitivity = menuui.sensitivity_validate(result.sensitivity, result.mouse_dpi)
	result.ads_sensitivity = menuui.ads_sensitivity_validate(result.ads_sensitivity, result.sensitivity, result.mouse_dpi)
	result.display_mode = clamp(result.display_mode, 0, 2)
	result.resolution_index = clamp(result.resolution_index, 0, i32(len(DISPLAY_RESOLUTIONS))-1)
	result.monitor_index = max(0, result.monitor_index)
	result.visuals = menuui.visual_settings_validate(result.visuals)
	result.quality = menuui.quality_settings_validate(result.quality)
	result.viewmodel = menuui.viewmodel_settings_validate(result.viewmodel)
	result.crosshair = menuui.crosshair_settings_validate(result.crosshair)
	defaults := menuui.default_bindings()
	for action in menuui.Binding_Action {
		for code, slot in result.bindings[action] {
			if !menuui.binding_valid(code) { result.bindings[action][slot] = defaults[action][slot] }
		}
		if result.bindings[action][0] == result.bindings[action][1] { result.bindings[action][1] = 0 }
	}
	return result
}

client_settings_load :: proc(path: string = CLIENT_SETTINGS_PATH) -> Client_Settings {
	settings := client_settings_defaults()
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil { return settings }
	defer delete(data)
	if json.unmarshal(data, &settings) != nil || settings.version != 1 {
		fmt.eprintln("[Settings] Invalid client preferences; using defaults.")
		return client_settings_defaults()
	}
	return client_settings_validate(settings)
}

client_settings_snapshot :: proc(client: ^Client) -> Client_Settings {
	return {version = 1, display_mode = i32(client.display_mode), resolution_index = client.resolution_index, monitor_index = client.monitor_index,
		fov = client.camera.fov * 180 / math.PI, sensitivity = client.sensitivity, mouse_dpi = client.mouse_dpi, show_fps = client.show_fps, vsync = client.vsync, bindings = client.bindings, hud = client.hud_settings,
		ads_sensitivity = client.ads_sensitivity, advanced_sensitivity = client.advanced_sensitivity, invert_mouse = client.invert_mouse,
		visuals = client.visual_settings, quality = client.quality_settings, viewmodel = client.viewmodel_settings, trails = client.trail_settings, crosshair = client.crosshair_settings}
}

client_settings_save :: proc(settings: Client_Settings, path: string = CLIENT_SETTINGS_PATH) -> bool {
	data, err := json.marshal(client_settings_validate(settings))
	if err != nil { return false }
	defer delete(data)
	if os.write_entire_file(path, data) != nil { fmt.eprintln("[Settings] Could not save client preferences."); return false }
	return true
}
