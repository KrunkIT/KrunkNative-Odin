package menu

import "core:math"
import "core:fmt"
import clay "../third_party/clay"

// Keep the final legacy entry for existing settings files; it is never editable.
Visual_Control :: enum { BRIGHTNESS, GAMMA, CONTRAST, SATURATION, AMBIENT, SUNLIGHT, FOG_DISTANCE }
Visual_Color :: enum { AMBIENT, SUNLIGHT, FOG, SKY }
Visual_Settings :: struct {
	values: [Visual_Control]f32,
	// Legacy settings are decoded for compatibility, then reset and ignored.
	color_override: [Visual_Color]bool,
	colors: [Visual_Color][3]f32,
}
Quality_Settings :: struct { smooth_textures: bool, anisotropy: i32 } // 0 = off; otherwise 2, 4, 8 or 16.

DEFAULT_VISUAL_SETTINGS :: Visual_Settings{values = {.BRIGHTNESS=1, .GAMMA=1, .CONTRAST=1, .SATURATION=1, .AMBIENT=1, .SUNLIGHT=1, .FOG_DISTANCE=1}, colors = {.AMBIENT={1,1,1}, .SUNLIGHT={1,1,1}, .FOG={1,1,1}, .SKY={1,1,1}}}
VISUAL_LABELS := #partial [Visual_Control]string{.BRIGHTNESS="Brightness", .GAMMA="Gamma", .CONTRAST="Contrast", .SATURATION="Saturation", .AMBIENT="Ambient strength", .SUNLIGHT="Sunlight strength"}
VISUAL_LIMITS := [Visual_Control][2]f32{.BRIGHTNESS={0.5,1.5}, .GAMMA={0.5,2}, .CONTRAST={0.5,1.5}, .SATURATION={0,2}, .AMBIENT={0,2}, .SUNLIGHT={0,2}, .FOG_DISTANCE={1,1}}
ANISOTROPY_LEVELS := [5]i32{0, 2, 4, 8, 16}

visual_settings_validate :: proc(settings: Visual_Settings) -> Visual_Settings {
	result := settings
	for control in Visual_Control {
		value := result.values[control]
		if math.is_nan(value) || math.is_inf(value) { value = 1 }
		result.values[control] = clamp(value, VISUAL_LIMITS[control][0], VISUAL_LIMITS[control][1])
	}
	result.values[.FOG_DISTANCE] = 1
	result.color_override = {}
	result.colors = DEFAULT_VISUAL_SETTINGS.colors
	return result
}

quality_settings_validate :: proc(settings: Quality_Settings) -> Quality_Settings {
	result := settings
	switch result.anisotropy { case 0, 2, 4, 8, 16: case: result.anisotropy = 0 }
	return result
}

settings_visuals :: proc(state: ^State) {
	s := state.scale
	settings_note("Graphics preview live. Save keeps your changes; Cancel restores them.", s)
	settings_section("Image", s)
	for control in Visual_Control {
		if control == .FOG_DISTANCE { continue }
		if control == .AMBIENT { settings_section("Lighting", s) }
		settings_slider(state, VISUAL_LABELS[control], fmt.tprintf("Visual%d", int(control)), state.settings_draft.visuals.values[control],
			VISUAL_LIMITS[control][0], VISUAL_LIMITS[control][1], {kind = .VISUAL_VALUE, index = i32(control)})
	}
	settings_note("Lighting strength multiplies each map's original values. 1.00 preserves the map defaults.", s)
	settings_note("Reset restores the original appearance of every map.", s)
	settings_button(state, "Reset visuals", "ResetVisuals", {kind = .VISUAL_RESET})
}

settings_quality :: proc(state: ^State, view: View) {
	settings_section("Quality", state.scale)
	if clay.UI(clay.ID("TextureFilteringRow"))(settings_row(state)) {
		settings_label("Texture filtering", state.scale)
		spacer()
		settings_dropdown_field(state, state.settings_draft.quality.smooth_textures ? "Smooth" : "Sharp", "TextureFiltering", .TEXTURE_FILTER)
	}
	if clay.UI(clay.ID("AnisotropyRow"))(settings_row(state)) {
		settings_label("Anisotropic filtering", state.scale)
		spacer()
		label := view.max_anisotropy < 2 ? "Unavailable" : state.settings_draft.quality.anisotropy < 2 ? "Off" : fmt.tprintf("%dx", state.settings_draft.quality.anisotropy)
		settings_dropdown_field(state, label, "Anisotropy", .ANISOTROPY, view.max_anisotropy >= 2)
	}
	settings_note("Sharp keeps the pixelated texture style. Smooth blends texels. Anisotropic filtering improves textures viewed at an angle.", state.scale)
}

settings_slider_value :: proc(state: ^State, view: View, action: Action) -> f32 {
	values := state.settings_draft
	if !state.settings_active {
		values.sensitivity, values.audio_volumes, values.visuals = view.sensitivity, view.audio_volumes, view.visuals
		values.fov = fov_validate(view.fov)
	}
	#partial switch action.kind {
	case .AUDIO_VOLUME: return values.audio_volumes[action.index]
	case .FOV: return values.fov
	case .VISUAL_VALUE: return values.visuals.values[Visual_Control(action.index)]
	}
	return values.sensitivity
}
