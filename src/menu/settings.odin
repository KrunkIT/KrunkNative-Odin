package menu

import "core:fmt"
import clay "../third_party/clay"

SETTINGS_ORANGE :: clay.Color{239, 110, 24, 255}
SETTINGS_BG :: clay.Color{39, 37, 44, 255}
SETTINGS_DARK :: clay.Color{29, 28, 33, 255}
SETTINGS_LINE :: clay.Color{73, 70, 79, 255}
SETTINGS_MUTED :: clay.Color{166, 164, 177, 255}
SETTINGS_TABS := [Settings_Tab]string{.MAIN = "Main", .INPUT = "Key binds", .VIDEO = "Video", .VISUALS = "Visuals", .GAMEPLAY = "Gameplay", .AUDIO = "Audio", .HUD = "HUD"}

settings_window :: proc(state: ^State, view: View) {
	s := state.scale
	values := state.settings_draft
	if clay.UI(clay.ID("Overlay"))({
		layout = {sizing = {width = clay.SizingFixed(1360*s), height = clay.SizingFixed(780*s)}, layoutDirection = .TopToBottom},
		backgroundColor = SETTINGS_BG, cornerRadius = clay.CornerRadiusAll(12*s),
		border = {color = {131, 127, 140, 255}, width = clay.BorderOutside(1)},
	}) {
		if clay.UI(clay.ID("SettingsBody"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}}}) {
			if clay.UI(clay.ID("SettingsSidebar"))({
				layout = {sizing = {width = clay.SizingFixed(232*s), height = clay.SizingGrow()}, layoutDirection = .TopToBottom},
				backgroundColor = SETTINGS_DARK, border = {color = SETTINGS_LINE, width = {right = 1}},
			}) {
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(80*s)}, padding = {left = u16(24*s)}, childAlignment = {y = .Center}}}) {
					text("SETTINGS", 28, s, SETTINGS_MUTED)
				}
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(8*s)), childGap = u16(4*s)}}) {
					for tab in Settings_Tab {
						settings_button(state, SETTINGS_TABS[tab], "SettingsTab", {kind = .SETTINGS_TAB, index = i32(tab)}, selected = tab == state.settings_tab, align_left = true)
					}
				}
				spacer()
				if state.settings_tab == .GAMEPLAY { settings_crosshair_preview(state) }
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = clay.PaddingAll(u16(24*s))}}) { text("KRODIN", 16, s, SETTINGS_MUTED) }
			}
			if clay.UI(clay.ID("SettingsContent"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
				if clay.UI(clay.ID("SettingsHeading"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(80*s)}, padding = {left = u16(32*s), right = u16(32*s)}, childAlignment = {y = .Center}}, backgroundColor = SETTINGS_DARK}) {
					text(SETTINGS_TABS[state.settings_tab], 28, s)
				}
				if clay.UI(clay.ID("SettingsPanel"))({
					layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32*s))},
					clip = {vertical = true, childOffset = clay.GetScrollOffset()},
				}) {
					switch state.settings_tab {
					case .MAIN:
						settings_section("General", s)
						settings_sensitivity(state)
						settings_slider(state, "Master volume", "MasterVolume", values.audio_volumes[0], 0, 1, {kind = .AUDIO_VOLUME})
						settings_display_rows(state, view)
						settings_fps_row(state)
					case .INPUT:
						settings_bindings(state)
					case .VIDEO:
						settings_section("Display", s)
						settings_display_rows(state, view)
						settings_toggle_row(state, "V-Sync", "VSync", values.vsync, {kind = .VSYNC})
						settings_note("Resolution applies in windowed mode. Borderless and fullscreen use the selected monitor's resolution.", s)
						settings_quality(state, view)
					case .VISUALS:
						settings_visuals(state)
					case .GAMEPLAY:
						settings_viewmodel(state)
						settings_trails(state)
						settings_crosshair(state)
					case .AUDIO:
						settings_section("Volume", s)
						labels := [4]string{"Master volume", "Effects volume", "Footsteps volume", "UI volume"}
						ids := [4]string{"MasterVolume", "EffectsVolume", "FootstepsVolume", "UiVolume"}
						for label, i in labels { settings_slider(state, label, ids[i], values.audio_volumes[i], 0, 1, {kind = .AUDIO_VOLUME, index = i32(i)}) }
						settings_note("Master volume affects every channel. Set a channel to 0% to mute it.", s)
					case .HUD:
						settings_section("Match", s)
						settings_toggle_row(state, "Timer", "HudTimer", !values.hud.hide_timer, {kind = .HUD_TOGGLE})
						settings_toggle_row(state, "Team round score", "HudRoundScore", !values.hud.hide_round_score, {kind = .HUD_TOGGLE, index = 1})
						settings_toggle_row(state, "Team game score", "HudGameScore", !values.hud.hide_game_score, {kind = .HUD_TOGGLE, index = 2})
						settings_note("Round score: objective points this round. Game score: rounds won.", s)
						settings_section("Performance", s)
						settings_fps_row(state)
					}
				}
				settings_scrollbar(state)
			}
		}
		if clay.UI(clay.ID("SettingsFooter"))({
			layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(88*s)}, padding = {left = u16(24*s), right = u16(24*s)}, childGap = u16(24*s), childAlignment = {y = .Center}},
			backgroundColor = SETTINGS_DARK, border = {color = SETTINGS_LINE, width = {top = 1}},
		}) {
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(184*s)}}}) { settings_button(state, "Cancel", "SettingsCancel", {kind = .SETTINGS_CANCEL}) }
			spacer()
			text(settings_number_hint(state), 16, s, state.number_invalid ? clay.Color{255,100,100,255} : SETTINGS_MUTED)
			spacer()
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(184*s)}}}) { settings_button(state, "Save", "SettingsSave", {kind = .SETTINGS_SAVE}, selected = true) }
		}
	}
	settings_dropdown_menu(state, view)
}

settings_button :: proc(state: ^State, label, name: string, action: Action, selected: bool = false, align_left: bool = false, enabled: bool = true) {
	s := state.scale
	// Cycling display mode keeps the same focus target as its action changes.
	id := clay.ID(name, action.kind == .DISPLAY_MODE ? 0 : u32(action.index))
	register(state, {id = id, action = action, enabled = enabled})
	color := selected ? SETTINGS_ORANGE : clay.Color{57, 54, 64, 255}
	if enabled && clay.PointerOver(id) { color = selected ? clay.Color{255, 128, 40, 255} : clay.Color{73, 68, 81, 255} }
	if state.pressed == id.id { color = {177, 76, 18, 255} }
	if clay.UI(id)({
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48*s)}, padding = {left = u16(20*s), right = u16(20*s)}, childAlignment = {x = align_left ? .Left : .Center, y = .Center}},
		backgroundColor = color, cornerRadius = clay.CornerRadiusAll(3*s),
		border = {color = state.focus == id.id ? WHITE : SETTINGS_LINE, width = clay.BorderOutside(state.focus == id.id ? 2 : 1)},
	}) { text(label, 21, s, enabled ? WHITE : SETTINGS_MUTED) }
}

settings_scrollbar :: proc(state: ^State) {
	data := clay.GetScrollContainerData(clay.ID("SettingsPanel"))
	if !data.found || data.contentDimensions.height <= data.scrollContainerDimensions.height+1 { return }
	s := state.scale
	height := data.scrollContainerDimensions.height-24*s
	thumb_height := max(32*s, height*data.scrollContainerDimensions.height/data.contentDimensions.height)
	progress := clamp(-data.scrollPosition[1]/(data.contentDimensions.height-data.scrollContainerDimensions.height), 0, 1)
	if clay.UI(clay.ID("SettingsScrollTrack"))({
		layout = {sizing = {width = clay.SizingFixed(max(14,16*s)), height = clay.SizingFixed(height)}, layoutDirection = .TopToBottom}, backgroundColor = SETTINGS_LINE, cornerRadius = clay.CornerRadiusAll(4*s),
		floating = {attachTo = .ElementWithId, parentId = clay.ID("SettingsPanel").id, zIndex = 11, pointerCaptureMode = .Passthrough, attachment = {element = .RightTop, parent = .RightTop}, offset = {-8*s, 12*s}},
	}) {
		if clay.UI()({layout = {sizing = {height = clay.SizingFixed(progress*(height-thumb_height))}}}) {}
		thumb_color := state.scrollbar_dragging ? SETTINGS_ORANGE : clay.PointerOver(clay.ID("SettingsScrollThumb")) ? WHITE : SETTINGS_MUTED
		if clay.UI(clay.ID("SettingsScrollThumb"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(thumb_height)}}, backgroundColor = thumb_color, cornerRadius = clay.CornerRadiusAll(4*s)}) {}
	}
}

settings_scrollbar_interact :: proc(state: ^State, input: Input) -> bool {
	if (state.page != .SETTINGS && state.page != .CONTROLS) || state.settings_dropdown != .NONE || input.escape {
		state.scrollbar_dragging = false
		return false
	}
	data := clay.GetScrollContainerData(clay.ID("SettingsPanel"))
	track := clay.GetElementData(clay.ID("SettingsScrollTrack"))
	thumb := clay.GetElementData(clay.ID("SettingsScrollThumb"))
	if !data.found || !track.found || !thumb.found {
		state.scrollbar_dragging = false
		return false
	}
	span := data.contentDimensions.height-data.scrollContainerDimensions.height
	travel := track.boundingBox.height-thumb.boundingBox.height
	if span <= 0 || travel <= 0 { state.scrollbar_dragging = false; return false }
	if input.down && !state.previous.down && clay.PointerOver(clay.ID("SettingsScrollTrack")) && contains(track.boundingBox, input.pointer) {
		state.scrollbar_dragging = true
		// Grabbing the thumb preserves its position. Clicking the empty track
		// centers it on the pointer, then lets the same press drag it further.
		state.scrollbar_grab = contains(thumb.boundingBox, input.pointer) ? input.pointer[1]-thumb.boundingBox.y : thumb.boundingBox.height/2
		state.pressed = 0
	}
	if !state.scrollbar_dragging { return false }
	if !input.down {
		state.scrollbar_dragging = false
		return true // Consume the release, even outside the scrollbar.
	}
	progress := clamp((input.pointer[1]-track.boundingBox.y-min(state.scrollbar_grab,thumb.boundingBox.height))/travel, 0, 1)
	data.scrollPosition[1] = -progress*span
	return true
}

settings_section :: proc(label: string, s: f32) {
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48*s)}, childAlignment = {y = .Center}}}) { text(label, 17, s, SETTINGS_ORANGE) }
}

settings_note :: proc(label: string, s: f32) {
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {top = u16(20*s), bottom = u16(16*s)}}}) { text(label, 16, s, SETTINGS_MUTED) }
}

// These rows reserve the same label column in every category.
settings_row :: proc(state: ^State) -> clay.ElementDeclaration {
	s := state.scale
	return {
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(72*s)}, childGap = u16(24*s), childAlignment = {y = .Center}},
		border = {color = {57, 54, 64, 255}, width = {bottom = 1}},
	}
}

settings_label :: proc(label: string, s: f32) {
	if clay.UI()({layout = {sizing = {width = clay.SizingFixed(304*s)}, childAlignment = {y = .Center}}}) { text(label, 21, s) }
}

settings_resolution_label :: proc(state: ^State, view: View) -> string {
	// Follow the live window until the user explicitly stages a windowed size.
	// The saved preset can differ from a resized, borderless or fullscreen window.
	if len(view.resolution_options) > 0 && (len(view.resolution) == 0 || state.settings_resolution_selected && state.settings_draft.display_mode == 0) {
		return view.resolution_options[clamp(int(state.settings_draft.resolution_index), 0, len(view.resolution_options)-1)]
	}
	return view.resolution
}

settings_display_rows :: proc(state: ^State, view: View) {
	s := state.scale
	values := state.settings_draft
	labels := [3]string{"Windowed", "Borderless", "Fullscreen"}
	if clay.UI(clay.ID("DisplayModeRow"))(settings_row(state)) {
		settings_label("Video mode", s)
		spacer()
		settings_dropdown_field(state, labels[clamp(values.display_mode, 0, 2)], "DisplayMode", .DISPLAY_MODE)
	}
	if state.settings_tab == .VIDEO {
		if clay.UI(clay.ID("MonitorRow"))(settings_row(state)) {
			settings_label("Monitor", s)
			spacer()
			label := len(view.monitor_names) > 0 ? view.monitor_names[clamp(int(values.monitor_index), 0, len(view.monitor_names)-1)] : "Primary monitor"
			settings_dropdown_field(state, shorten(label, 28), "Monitor", .MONITOR, len(view.monitor_names) > 0)
		}
	}
	if clay.UI(clay.ID("ResolutionRow"))(settings_row(state)) {
		settings_label("Window resolution", s)
		spacer()
		label := settings_resolution_label(state, view)
		settings_dropdown_field(state, label, "Resolution", .RESOLUTION, len(view.resolution_options) > 0)
	}
}

settings_toggle_row :: proc(state: ^State, label, name: string, value: bool, action: Action) {
	if clay.UI(clay.ID(fmt.tprintf("%sRow", name)))(settings_row(state)) {
		settings_label(label, state.scale)
		spacer()
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(128*state.scale)}}}) {
			settings_button(state, value ? "On" : "Off", name, action, selected = value)
		}
	}
}

settings_fps_row :: proc(state: ^State) {
	if clay.UI(clay.ID("FpsRow"))(settings_row(state)) {
		settings_label("Show FPS", state.scale)
		spacer()
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(128*state.scale)}}}) {
			settings_button(state, state.settings_draft.show_fps ? "On" : "Off", "Fps", {kind = .FPS}, selected = state.settings_draft.show_fps)
		}
	}
}

settings_slider :: proc(state: ^State, label, name: string, value, minimum, maximum: f32, action: Action, step: f32 = 0.05) {
	s := state.scale
	if clay.UI(clay.ID(fmt.tprintf("%sRow", name)))(settings_row(state)) {
		settings_label(label, s)
		id := clay.ID(name)
		register(state, {id = id, enabled = true, slider = true, action = action, slider_min = minimum, slider_max = maximum, slider_step = step})
		if clay.UI(id)({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(44*s)}, childAlignment = {y = .Center}}, border = {color = WHITE, width = clay.BorderOutside(state.focus == id.id ? 1 : 0)}}) {
			fill_id := clay.ID(fmt.tprintf("%sFill", name))
			progress := clamp((value-minimum)/(maximum-minimum), 0.001, 0.999)
			if clay.UI(fill_id)({layout = {sizing = {width = clay.SizingPercent(progress), height = clay.SizingFixed(4*s)}}, backgroundColor = SETTINGS_ORANGE}) {
				if clay.UI(clay.ID(fmt.tprintf("%sThumb", name)))({layout = {sizing = {width = clay.SizingFixed(12*s), height = clay.SizingFixed(28*s)}}, backgroundColor = SETTINGS_ORANGE, cornerRadius = clay.CornerRadiusAll(3*s), floating = {attachTo = .ElementWithId, parentId = fill_id.id, zIndex = 11, pointerCaptureMode = .Passthrough, clipTo = .AttachedParent, attachment = {element = .CenterCenter, parent = .RightCenter}}}) {}
			}
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(4*s)}}, backgroundColor = {137, 133, 146, 255}}) {}
		}
		value_id := clay.ID(fmt.tprintf("%sValue", name))
		register(state, {id=value_id, action=action, enabled=true, number=true, slider_min=minimum, slider_max=maximum})
		editing := state.number_edit == .SLIDER && state.number_control.id.id == value_id.id
		if clay.UI(value_id)({
			layout = {sizing = {width = clay.SizingFixed(128*s), height = clay.SizingFixed(44*s)}, padding={left=u16(8*s), right=u16(8*s)}, childAlignment = {x = .Center, y = .Center}},
			backgroundColor = editing && state.number_replace ? SETTINGS_ORANGE : clay.Color{231, 229, 235, 255}, cornerRadius = clay.CornerRadiusAll(4*s),
			border={color=editing && state.number_invalid ? clay.Color{255,70,70,255} : state.focus == value_id.id ? WHITE : SETTINGS_LINE, width=clay.BorderOutside(editing || state.focus == value_id.id ? 2 : 0)},
			clip={horizontal=editing, childOffset=clay.GetScrollOffset()},
		}) {
			label := action.kind == .AUDIO_VOLUME ? fmt.tprintf("%g%%", value*100) : fmt.tprintf("%g", value)
			if editing { label = fmt.tprintf("%s|", string(state.number_buffer[:state.number_length])) }
			text(label, 20, s, SETTINGS_DARK)
		}
	}
}
