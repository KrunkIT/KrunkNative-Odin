package menu

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import clay "../third_party/clay"
import shared "../shared"

DEFAULT_MOUSE_DPI :: 800
MIN_MOUSE_DPI :: 100
MAX_MOUSE_DPI :: 100000
MIN_CM360 :: 0.1
MAX_CM360 :: 2000.0
DEFAULT_FOV :: 90.0
MIN_FOV :: 60.0
MAX_FOV :: 120.0
Settings_Number :: enum { NONE, DPI, CM360, ADS_CM360 }

// FOV is the vertical world-camera angle, in degrees.
fov_validate :: proc(fov: f32) -> f32 {
	if math.is_nan(fov) || math.is_inf(fov) || fov <= 0 { return DEFAULT_FOV }
	return clamp(fov, MIN_FOV, MAX_FOV)
}

mouse_dpi_validate :: proc(dpi: f32) -> f32 {
	if math.is_nan(dpi) || math.is_inf(dpi) || dpi <= 0 { return DEFAULT_MOUSE_DPI }
	return math.round(clamp(dpi, MIN_MOUSE_DPI, MAX_MOUSE_DPI))
}

cm360_from_sensitivity :: proc(sensitivity, dpi: f32) -> f32 {
	factor := sensitivity
	if math.is_nan(factor) || math.is_inf(factor) || factor <= 0 { factor = 1 }
	return (2*math.PI*2.54) / (mouse_dpi_validate(dpi) * shared.GAME_CONSTANTS.mouse_sensitivity * factor)
}

sensitivity_from_cm360 :: proc(cm360, dpi: f32) -> f32 {
	return (2*math.PI*2.54) / (mouse_dpi_validate(dpi) * shared.GAME_CONSTANTS.mouse_sensitivity * cm360)
}

sensitivity_validate :: proc(sensitivity, dpi: f32) -> f32 {
	factor := sensitivity
	if math.is_nan(factor) || math.is_inf(factor) || factor <= 0 { factor = 1 }
	cm360 := cm360_from_sensitivity(factor, dpi)
	if cm360 < MIN_CM360 || cm360 > MAX_CM360 {
		return sensitivity_from_cm360(clamp(cm360, MIN_CM360, MAX_CM360), dpi)
	}
	return factor
}

ads_sensitivity_validate :: proc(ads, hipfire, dpi: f32) -> f32 {
	if math.is_nan(ads) || math.is_inf(ads) || ads <= 0 { return sensitivity_validate(hipfire, dpi) }
	return sensitivity_validate(ads, dpi)
}

settings_sensitivity :: proc(state: ^State) {
	settings_number_row(state, "Mouse DPI", "MouseDPI", .DPI)
	settings_number_row(state, "Hipfire (cm/360)", "Sensitivity", .CM360)
	settings_toggle_row(state, "Invert mouse", "InvertMouse", state.settings_draft.invert_mouse, {kind = .INVERT_MOUSE})
	settings_toggle_row(state, "Advanced sensitivity", "AdvancedSensitivity", state.settings_draft.advanced_sensitivity, {kind = .ADVANCED_SENSITIVITY})
	if state.settings_draft.advanced_sensitivity {
		settings_number_row(state, "ADS (cm/360)", "AdsSensitivity", .ADS_CM360)
	}
	message := state.settings_draft.advanced_sensitivity ? "Hipfire and fully aimed ADS each use their own cm/360, independent of FOV and weapon zoom. Invert mouse reverses vertical look." : "Enter your DPI and hipfire cm/360. FOV changes preserve this distance. Enable Advanced sensitivity to set ADS separately; otherwise ADS scales with weapon zoom."
	if state.number_invalid {
		message = state.number_edit == .DPI ? "Enter a whole-number DPI from 100 to 100000." : "Enter a cm/360 value from 0.1 to 2000."
	}
	settings_note(message, state.scale)
}

settings_number_value :: proc(state: ^State, field: Settings_Number) -> f32 {
	if field == .DPI { return mouse_dpi_validate(state.settings_draft.mouse_dpi) }
	if field == .ADS_CM360 { return cm360_from_sensitivity(ads_sensitivity_validate(state.settings_draft.ads_sensitivity, state.settings_draft.sensitivity, state.settings_draft.mouse_dpi), state.settings_draft.mouse_dpi) }
	return cm360_from_sensitivity(state.settings_draft.sensitivity, state.settings_draft.mouse_dpi)
}

settings_number_id :: proc(field: Settings_Number) -> clay.ElementId {
	return clay.ID(field == .DPI ? "MouseDPI" : field == .ADS_CM360 ? "AdsSensitivity" : "Sensitivity")
}

settings_number_row :: proc(state: ^State, label, name: string, field: Settings_Number) {
	s := state.scale
	if clay.UI(clay.ID(fmt.tprintf("%sRow", name)))(settings_row(state)) {
		settings_label(label, s)
		spacer()
		id := clay.ID(name)
		editing := state.number_edit == field
		register(state, {id=id, action={kind=.SETTINGS_NUMBER, index=i32(field)}, enabled=true})
		value := settings_number_value(state, field)
		text_value := field == .DPI ? fmt.tprintf("%.0f", value) : fmt.tprintf("%.3f", value)
		if editing { text_value = fmt.tprintf("%s|", string(state.number_buffer[:state.number_length])) }
		if clay.UI(id)({
			layout={sizing={width=clay.SizingFixed(360*s), height=clay.SizingFixed(48*s)}, padding={left=u16(16*s), right=u16(16*s)}, childAlignment={y=.Center}},
			backgroundColor=editing && state.number_replace ? SETTINGS_ORANGE : clay.Color{231,229,235,255}, cornerRadius=clay.CornerRadiusAll(4*s),
			border={color=state.number_invalid && editing ? clay.Color{255,70,70,255} : state.focus == id.id ? WHITE : SETTINGS_LINE, width=clay.BorderOutside(editing || state.focus == id.id ? 2 : 1)},
		}) { text(text_value, 20, s, SETTINGS_DARK) }
	}
}

settings_number_begin :: proc(state: ^State, field: Settings_Number) {
	state.number_edit, state.number_invalid, state.number_replace, state.number_changed = field, false, true, false
	value := settings_number_value(state, field)
	label := field == .DPI ? fmt.tprintf("%.0f", value) : fmt.tprintf("%.6f", value)
	state.number_length = copy(state.number_buffer[:], transmute([]u8)label)
	state.pressed = 0
}

settings_number_commit :: proc(state: ^State) -> bool {
	if !state.number_changed { state.number_edit = .NONE; return true }
	value, ok := strconv.parse_f32(strings.trim_space(string(state.number_buffer[:state.number_length])))
	ok = ok && !math.is_nan(value) && !math.is_inf(value)
	if state.number_edit == .DPI {
		ok = ok && value >= MIN_MOUSE_DPI && value <= MAX_MOUSE_DPI && math.round(value) == value
	} else { ok = ok && value >= MIN_CM360 && value <= MAX_CM360 }
	if !ok { state.number_invalid = true; return false }
	cm360 := settings_number_value(state, .CM360)
	ads_cm360 := settings_number_value(state, .ADS_CM360)
	switch state.number_edit {
	case .DPI:
		state.settings_draft.mouse_dpi = value
		state.settings_draft.sensitivity = sensitivity_from_cm360(cm360, value)
		state.settings_draft.ads_sensitivity = sensitivity_from_cm360(ads_cm360, value)
	case .CM360: state.settings_draft.sensitivity = sensitivity_from_cm360(value, state.settings_draft.mouse_dpi)
	case .ADS_CM360: state.settings_draft.ads_sensitivity = sensitivity_from_cm360(value, state.settings_draft.mouse_dpi)
	case .NONE:
	}
	state.number_edit, state.number_invalid = .NONE, false
	return true
}

// Return false after a successful outside-click/Tab commit so normal navigation
// can continue. Enter and Escape affect only the number currently being edited.
settings_number_interact :: proc(state: ^State, input: Input) -> bool {
	if input.escape && !state.previous.escape {
		state.number_edit, state.number_invalid, state.pressed = .NONE, false, 0
		return true
	}
	if input.clear_text { state.number_replace = true }
	if input.backspace && !state.previous.backspace {
		state.number_length = state.number_replace ? 0 : max(0, state.number_length-1)
		state.number_replace, state.number_changed, state.number_invalid = false, true, false
	}
	for char in input.text {
		if char < 32 || char >= 127 || char == '`' { continue }
		if state.number_replace { state.number_length, state.number_replace = 0, false }
		if state.number_length < len(state.number_buffer) {
			state.number_buffer[state.number_length] = u8(char)
			state.number_length += 1
			state.number_changed, state.number_invalid = true, false
		}
	}
	if input.enter && !state.previous.enter { settings_number_commit(state); return true }
	if input.tab && !state.previous.tab || input.down && !state.previous.down && !clay.PointerOver(settings_number_id(state.number_edit)) {
		return !settings_number_commit(state)
	}
	return true
}
