package main

import "core:fmt"
import menuui "../menu"
import clay "../third_party/clay"
import shared "../shared"
import kproto "../krunker"

menu_test_measure :: proc "c" (text: clay.StringSlice, config: ^clay.TextElementConfig, user: rawptr) -> clay.Dimensions {
	return {f32(text.length) * f32(config.fontSize) * 0.65, f32(config.fontSize)}
}

menu_test_frame :: proc(state: ^menuui.State, view: menuui.View, input: menuui.Input, width: f32 = 1280, height: f32 = 720) -> menuui.Action {
	menuui.build(state, view, input, width, height, PHYSICS_DT)
	return menuui.interact(state, input, view)
}

menu_test_click :: proc(state: ^menuui.State, view: menuui.View, id: clay.ElementId) -> menuui.Action {
	box := clay.GetElementData(id).boundingBox
	input := menuui.Input{pointer = {box.x + box.width / 2, box.y + box.height / 2}, down = true}
	menu_test_frame(state, view, input)
	input.down = false
	return menu_test_frame(state, view, input)
}

test_menu :: proc() -> bool {
	state := menuui.State{}
	if !menuui.init(&state, menu_test_measure, nil) { return false }
	defer menuui.fini(&state)
	classes: [len(shared.CLASSES_LIST)]menuui.Class
	for class, i in shared.CLASSES_LIST {
		classes[i] = {id = i32(i), name = class.name, weapon = "Primary weapon", available = shared.class_is_in_rotation(i32(i)), reason = "Class restricted by server"}
	}
	players := [?]menuui.Player{
		{name = "A very long competitive player name that must fit", class_name = "Run N Gun", team = 1, is_you = true},
		{name = "Opponent", class_name = "Hunter", team = 2},
	}
	view := menuui.View{classes = classes[:], players = players[:], online = true, ready = true, selected_class = 2, confirmed_class = 2, confirmed_team = 1, map_name = "Sandstorm", mode = "Hardpoint", lobby_name = "Competitive lobby", resolution = "1920 x 1080", sensitivity = 1,
		teams = {{id=1, name="Alpha", capacity=4, available=true}, {id=2, name="Bravo", capacity=4, available=true}}}
	view.presentation = .COMPETITIVE
	sizes := [?][2]f32{{1280,720}, {1920,1080}, {2560,1600}}
	for size in sizes {
		for page in menuui.Page {
			state.page = page
			commands := menuui.build(&state, view, {}, size[0], size[1], PHYSICS_DT)
			if commands.length == 0 || state.errors != 0 { fmt.eprintln("Menu layout/ABI test failed"); return false }
			ids := [?]string{"Header", "Page", "Footer"}
			for id in ids {
				data := clay.GetElementData(clay.ID(id)); box := data.boundingBox
				if !data.found || box.x < 0 || box.y < 0 || box.width <= 0 || box.height <= 0 || box.x+box.width > size[0]+1 || box.y+box.height > size[1]+1 {
					fmt.printf("Menu bounds failed: %v %v %s %v\n", page, size, id, box); return false
				}
			}
			if page != .HOME {
				box := clay.GetElementData(clay.ID("Overlay")).boundingBox
				if box.x < 0 || box.y < 0 || box.x+box.width > size[0]+1 || box.y+box.height > size[1]+1 { fmt.println("Modal bounds failed", box); return false }
			}
		}
	}
	state.page = .HOME
	menu_test_frame(&state, view, {})
	left := clay.GetElementData(clay.ID("Team",1)).boundingBox
	right := clay.GetElementData(clay.ID("Team",2)).boundingBox
	if abs(left.width-right.width)>1 || abs(left.y-right.y)>1 { return false }
	box := clay.GetElementData(clay.ID("Play")).boundingBox
	menu_test_frame(&state, view, {pointer = {box.x+5,box.y+5}, down = true})
	if menu_test_frame(&state, view, {pointer = {0,0}}).kind != .NONE { return false }
	if menu_test_click(&state, view, clay.ID("Play")).kind != .PLAY { return false }
	view.play_reason = "Choose a team"
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("Play")).kind != .NONE { return false }
	view.play_reason = ""
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("JoinTeam",2)).index != 2 { return false }
	// The menu must not turn a pending request into confirmed membership.
	view.team_pending = true; view.requested_team = 2
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("JoinTeam",2)).kind != .NONE || view.confirmed_team != 1 { return false }
	view.team_pending = false
	// Class selection lives on the lobby. Keyboard focus scrolls the strip.
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("Class",2)).index != 2 { return false }
	state.focus = clay.ID("Class",4).id
	if menu_test_frame(&state, view, {enter=true}).kind != .NONE { return false }
	menu_test_frame(&state, view, {})
	state.focus = clay.ID("Play").id
	if menu_test_frame(&state, view, {enter=true}).kind != .PLAY { return false }
	menu_test_frame(&state, view, {})
	view.audio_volumes = {0.8, 1, 0.5, 0}
	view.bindings = menuui.default_bindings()
	view.resolution_options = []string{"1280 x 720", "1920 x 1080", "2560 x 1440"}
	view.monitor_names = []string{"Primary monitor", "Second monitor"}
	menu_test_click(&state, view, clay.ID("Settings",u32(menuui.Page.SETTINGS)))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("SettingsTab", u32(menuui.Settings_Tab.MAIN)))
	menu_test_frame(&state, view, {})
	if state.page != .SETTINGS { return false }
	// Lobby controls cannot activate through an overlay.
	draft_before_lobby_click := state.settings_draft
	if menu_test_click(&state, view, clay.ID("Play")).kind != .NONE { return false }
	// The same coordinates can legitimately hit a settings control.
	state.settings_draft = draft_before_lobby_click
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("MouseDPI"))
	menu_test_frame(&state, view, {text="1600"})
	menu_test_frame(&state, view, {enter=true})
	menu_test_frame(&state, view, {})
	if state.settings_draft.mouse_dpi != 1600 || abs(menuui.cm360_from_sensitivity(state.settings_draft.sensitivity, 1600)-menuui.cm360_from_sensitivity(1, menuui.DEFAULT_MOUSE_DPI))>0.0001 { fmt.println("DPI changes must preserve cm/360"); return false }
	menu_test_click(&state, view, clay.ID("Sensitivity"))
	menu_test_frame(&state, view, {text="`35.5"})
	value := menu_test_frame(&state, view, {enter=true})
	if value.kind != .NONE || abs(menuui.cm360_from_sensitivity(state.settings_draft.sensitivity,1600)-35.5)>0.0001 || view.sensitivity != 1 { fmt.println("Sensitivity must accept cm/360 without changing committed values"); return false }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Sensitivity"))
	menu_test_frame(&state, view, {text="0"})
	menu_test_frame(&state, view, {enter=true})
	if !state.number_invalid || state.number_edit != .CM360 || abs(menuui.cm360_from_sensitivity(state.settings_draft.sensitivity,1600)-35.5)>0.0001 { fmt.println("Invalid cm/360 must not change the draft"); return false }
	menu_test_frame(&state, view, {})
	menu_test_frame(&state, view, {escape=true})
	if state.page != .SETTINGS || state.number_edit != .NONE { fmt.println("Escape must cancel only number entry"); return false }
	menu_test_frame(&state, view, {})
	if clay.GetElementData(clay.ID("AdsSensitivity")).found { fmt.println("ADS entry must be hidden until Advanced is enabled"); return false }
	menu_test_click(&state, view, clay.ID("AdvancedSensitivity"))
	menu_test_frame(&state, view, {})
	if !state.settings_draft.advanced_sensitivity || !clay.GetElementData(clay.ID("AdsSensitivity")).found { fmt.println("Advanced sensitivity must reveal the ADS entry"); return false }
	menu_test_click(&state, view, clay.ID("AdsSensitivity"))
	menu_test_frame(&state, view, {text="60"})
	menu_test_frame(&state, view, {enter=true})
	menu_test_frame(&state, view, {})
	if abs(menuui.cm360_from_sensitivity(state.settings_draft.ads_sensitivity,1600)-60)>0.0001 || abs(menuui.cm360_from_sensitivity(state.settings_draft.sensitivity,1600)-35.5)>0.0001 { fmt.println("ADS entry must be independent of hipfire"); return false }
	menu_test_click(&state, view, clay.ID("MouseDPI"))
	menu_test_frame(&state, view, {text="3200"})
	menu_test_frame(&state, view, {enter=true})
	menu_test_frame(&state, view, {})
	if abs(menuui.cm360_from_sensitivity(state.settings_draft.ads_sensitivity,3200)-60)>0.0001 || abs(menuui.cm360_from_sensitivity(state.settings_draft.sensitivity,3200)-35.5)>0.0001 { fmt.println("DPI changes must preserve both sensitivities"); return false }
	menu_test_click(&state, view, clay.ID("InvertMouse"))
	menu_test_frame(&state, view, {})
	if !state.settings_draft.invert_mouse || view.invert_mouse || view.advanced_sensitivity { fmt.println("Advanced and inversion changes must remain staged"); return false }
	// Audio sliders retain their own channel and range when using the keyboard.
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("SettingsTab", u32(menuui.Settings_Tab.AUDIO)))
	for name, i in ([4]string{"MasterVolume", "EffectsVolume", "FootstepsVolume", "UiVolume"}) {
		menu_test_frame(&state, view, {})
		state.focus = clay.ID(name).id
		value = menu_test_frame(&state, view, {right = true})
		if value.kind != .NONE || abs(state.settings_draft.audio_volumes[i] - min(1, view.audio_volumes[i]+0.05)) > 0.001 {
			fmt.println("Audio slider keyboard routing failed", name, value, state.settings_tab, state.number_edit, state.settings_draft.audio_volumes); return false
		}
	}
	// Tab scrolls focused audio controls into view; dragging adjusts that channel.
	menu_test_frame(&state, view, {})
	state.focus = clay.ID("FootstepsVolume").id
	menu_test_frame(&state, view, {tab = true})
	menu_test_frame(&state, view, {})
	box = clay.GetElementData(clay.ID("UiVolume")).boundingBox
	value = menu_test_frame(&state, view, {pointer = {box.x+box.width*0.25, box.y+box.height/2}, down = true})
	if value.kind != .NONE || abs(state.settings_draft.audio_volumes[3]-0.25)>0.001 { fmt.println("Audio slider dragging failed", value); return false }
	// Clicking the thumb itself must keep dragging the slider underneath it.
	menu_test_frame(&state, view, {})
	box = clay.GetElementData(clay.ID("UiVolumeThumb")).boundingBox
	menu_test_frame(&state, view, {pointer = {box.x+box.width/2, box.y+box.height/2}, down = true})
	if state.pressed != clay.ID("UiVolume").id { fmt.println("Volume thumb blocked slider input"); return false }
	menu_test_frame(&state, view, {})
	view.active = true
	if menu_test_frame(&state, view, {escape=true}).kind != .NONE || state.page != .HOME { return false }
	// Escape cancels the entire draft, including edits on other tabs.
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Settings",u32(menuui.Page.SETTINGS)))
	menu_test_frame(&state, view, {})
	if state.settings_draft.sensitivity != view.sensitivity || state.settings_draft.audio_volumes != view.audio_volumes { fmt.println("Settings cancellation failed"); return false }
	if state.settings_draft.advanced_sensitivity || state.settings_draft.invert_mouse { fmt.println("Cancel must discard Advanced and inversion changes"); return false }
	menu_test_click(&state, view, clay.ID("SettingsTab", u32(menuui.Settings_Tab.INPUT)))
	menu_test_frame(&state, view, {})
	// Both slots are editable; capture consumes navigation keys and buttons.
	menu_test_click(&state, view, clay.ID("Binding", 1))
	if state.binding_capture != 2 { fmt.println("Key binding listener did not open"); return false }
	if menu_test_frame(&state, view, {binding_pressed = 'I'}).kind != .NONE || state.settings_draft.bindings[.FORWARD] != ([2]i32{'W', 'I'}) || view.bindings[.FORWARD][1] != 0 { fmt.println("Alternate binding capture failed"); return false }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Binding", 1))
	menu_test_frame(&state, view, {binding_pressed = 96})
	if state.binding_capture == 0 || !state.binding_reserved { fmt.println("Backtick must remain reserved"); return false }
	menu_test_frame(&state, view, {escape = true})
	if state.page != .SETTINGS || state.binding_capture != 0 || state.settings_draft.bindings[.FORWARD][1] != 'I' { fmt.println("Escape must cancel only key capture"); return false }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Binding", 1))
	menu_test_frame(&state, view, {binding_pressed = -4})
	if state.settings_draft.bindings[.FORWARD][1] != -4 { fmt.println("Mouse binding capture failed"); return false }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Binding", 1))
	menu_test_frame(&state, view, {binding_pressed = 261})
	if state.settings_draft.bindings[.FORWARD][1] != 0 { fmt.println("Delete must clear a binding"); return false }
	menu_test_frame(&state, view, {})
	box = clay.GetElementData(clay.ID("SettingsPanel")).boundingBox
	menu_test_frame(&state, view, {pointer = {box.x+box.width/2, box.y+box.height/2}, scroll = {0, -100}})
	menu_test_frame(&state, view, {})
	last_binding := clay.GetElementData(clay.ID("BindingRow", u32(menuui.Binding_Action.FULLSCREEN))).boundingBox
	if !clay.GetElementData(clay.ID("SettingsScrollTrack")).found || last_binding.y < box.y || last_binding.y+last_binding.height > box.y+box.height+1 { fmt.println("Input settings must scroll to the final binding"); return false }
	menu_test_click(&state, view, clay.ID("SettingsTab", u32(menuui.Settings_Tab.VIDEO)))
	menu_test_frame(&state, view, {})
	if abs(clay.GetScrollContainerData(clay.ID("SettingsPanel")).scrollPosition[1]) > 0.001 { fmt.println("Changing settings tab must reset scrolling"); return false }
	menu_test_click(&state, view, clay.ID("DisplayMode"))
	menu_test_frame(&state, view, {})
	menu_test_frame(&state, view, {down_key = true})
	menu_test_frame(&state, view, {})
	menu_test_frame(&state, view, {down_key = true})
	menu_test_frame(&state, view, {})
	menu_test_frame(&state, view, {enter = true})
	if state.settings_draft.display_mode != 2 || state.focus != clay.ID("DisplayMode").id { fmt.println("Display mode lost keyboard focus"); return false }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Resolution"))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("SettingsOption", 1))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Monitor"))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("SettingsOption", 1))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("VSync"))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("SettingsTab", u32(menuui.Settings_Tab.HUD)))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Fps"))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("HudTimer"))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("HudRoundScore", 1))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("HudGameScore", 2))
	menu_test_frame(&state, view, {})
	value = menu_test_click(&state, view, clay.ID("SettingsSave"))
	if value.kind != .SETTINGS_SAVE || state.page != .HOME || state.settings_draft.display_mode != 2 || state.settings_draft.resolution_index != 1 || !state.settings_draft.show_fps { fmt.println("Settings Save failed"); return false }
	if !state.settings_draft.vsync || state.settings_draft.monitor_index != 1 || state.settings_draft.hud != (menuui.HUD_Settings{true, true, true}) { fmt.println("Video and HUD settings were not staged"); return false }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Settings",u32(menuui.Page.SETTINGS)))
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("SettingsCancel")).kind != .NONE || state.page != .HOME { fmt.println("Settings Cancel failed"); return false }
	menu_test_frame(&state, view, {})
	if menu_test_frame(&state, view, {escape=true}).kind != .PLAY { return false }
	// Offline connection screen: editable invite, paste, join, and errors.
	view.online=false; view.active=false; view.local_practice=false
	view.join_status="Connection failed. Please check the invite and try again."
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("JoinLink")).kind != .NONE { return false }
	if clay.GetElementData(clay.ID("Login")).found { return false }
	view.browser_access_supported = true
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("Login")).kind != .LOGIN { fmt.println("Login must be available without an invite"); return false }
	menu_test_click(&state, view, clay.ID("Invite"))
	menu_test_frame(&state, view, {text="krunk://localhost:21015"})
	if menuui.invite(&state) != "krunk://localhost:21015" { return false }
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("JoinLink")).kind != .JOIN_LINK { return false }
	view.auth_pending = true
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("Login")).kind != .NONE || menu_test_click(&state, view, clay.ID("JoinLink")).kind != .NONE { fmt.println("Pending Login must disable duplicate Login and Join"); return false }
	if menu_test_click(&state, view, clay.ID("CancelJoin")).kind != .CANCEL_JOIN { return false }
	view.auth_pending = false
	// Opening session from the connection screen must not duplicate field IDs.
	state.page=.SESSION
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("Login")).kind != .LOGIN { fmt.println("Session controls must expose Login"); return false }
	if state.errors != 0 { return false }
	fmt.println("Competitive lobby layout, modal, selection, invite, mouse and keyboard tests OK")
	return test_slider_numbers() && test_crosshair_menu() && test_settings_scrolling() && test_graphics_menu() && test_standard_menu() && test_lobby_packets() && test_live_lobby_records()
}

test_slider_numbers :: proc() -> bool {
	state := menuui.State{page=.SETTINGS}
	if !menuui.init(&state, menu_test_measure, nil) { return false }
	defer menuui.fini(&state)
	view := menuui.View{sensitivity=1, fov=90, visuals=menuui.DEFAULT_VISUAL_SETTINGS, viewmodel=menuui.DEFAULT_VIEWMODEL_SETTINGS, crosshair=menuui.DEFAULT_CROSSHAIR_SETTINGS, audio_volumes={0.8,1,0.5,0}}
	count := 0
	for tab in ([4]menuui.Settings_Tab{.MAIN,.VISUALS,.GAMEPLAY,.AUDIO}) {
		menuui.activate(&state, {action={kind=.SETTINGS_TAB, index=i32(tab)}})
		menu_test_frame(&state, view, {})
		controls := state.controls
		for control in controls[:state.control_count] {
			if !control.number { continue }
			count += 1
			menuui.focus_visible(control, .SETTINGS)
			menu_test_frame(&state, view, {})
			menu_test_click(&state, view, control.id)
			if state.number_edit != .SLIDER || state.number_control.id.id != control.id.id { fmt.println("Every slider value must open a number editor", tab, control.action); return false }
			expected := control.slider_min+(control.slider_max-control.slider_min)*0.375
			text := control.action.kind == .AUDIO_VOLUME ? "37.5%" : fmt.tprintf("%g", expected)
			menu_test_frame(&state, view, {text=text})
			action := menu_test_frame(&state, view, {enter=true})
			actual := menuui.settings_slider_value(&state, view, control.action)
			if state.number_edit != .NONE || action.kind != .NONE || abs(actual-expected)>0.0001 { fmt.println("Manual entry must update the matching draft value in its displayed units", tab, control.action, actual, expected); return false }
			menu_test_frame(&state, view, {})
		}
	}
	if count != 28 { fmt.println("Missing editable slider values", count); return false }
	menuui.activate(&state, {action={kind=.SETTINGS_TAB, index=i32(menuui.Settings_Tab.GAMEPLAY)}})
	menu_test_frame(&state, view, {})
	gap: menuui.Control
	for control in state.controls[:state.control_count] { if control.id.id == clay.ID("CrosshairGapValue").id { gap = control } }
	menuui.focus_visible(gap, .SETTINGS)
	menu_test_frame(&state, view, {})
	before := state.settings_draft.crosshair
	for invalid in ([]string{"", "not a number", "NaN", "Inf", "1e99", "-101", "101"}) {
		menu_test_click(&state, view, gap.id)
		menu_test_frame(&state, view, {clear_text=true, backspace=true})
		menu_test_frame(&state, view, {text=invalid})
		menu_test_frame(&state, view, {enter=true})
		if !state.number_invalid || state.number_edit != .SLIDER || state.settings_draft.crosshair != before { fmt.println("Invalid manual values must leave the draft intact", invalid); return false }
		menu_test_frame(&state, view, {escape=true})
		if state.page != .SETTINGS || state.number_edit != .NONE { fmt.println("Escape must discard only the number edit"); return false }
		menu_test_frame(&state, view, {})
	}
	menu_test_click(&state, view, gap.id)
	menu_test_frame(&state, view, {text="-3.125"})
	menu_test_frame(&state, view, {tab=true})
	if state.number_edit != .NONE || state.settings_draft.crosshair.values[.GAP] != -3.125 || state.focus != clay.ID("CrosshairDot",u32(menuui.Crosshair_Toggle.DOT)).id { fmt.println("Tab must commit precise negative values and continue navigation"); return false }
	menu_test_frame(&state, view, {})
	// Opening and accepting an untouched field must preserve its exact float.
	state.settings_draft.crosshair.values[.GAP] = -3.1234567
	menu_test_click(&state, view, gap.id)
	menu_test_frame(&state, view, {enter=true})
	if state.settings_draft.crosshair.values[.GAP] != -3.1234567 { fmt.println("An untouched number editor must not round the stored value"); return false }
	menu_test_frame(&state, view, {})
	state.focus = gap.id.id
	menu_test_frame(&state, view, {enter=true})
	menu_test_frame(&state, view, {text="-7.75"})
	action := menu_test_click(&state, view, clay.ID("SettingsSave"))
	if action.kind != .SETTINGS_SAVE || state.settings_draft.crosshair.values[.GAP] != -7.75 { fmt.println("Save must commit an active numeric edit before saving the draft"); return false }
	state.page = .SETTINGS
	menu_test_frame(&state, view, {})
	for control in state.controls[:state.control_count] { if control.id.id == gap.id.id { menuui.focus_visible(control, .SETTINGS) } }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, gap.id)
	menu_test_frame(&state, view, {text="-4.75"})
	menu_test_click(&state, view, clay.ID("SettingsCancel"))
	state.page = .SETTINGS
	menu_test_frame(&state, view, {})
	if state.settings_draft.crosshair != view.crosshair || state.settings_draft.viewmodel != view.viewmodel || state.settings_draft.audio_volumes != view.audio_volumes { fmt.println("Cancel must discard manually entered values across all settings"); return false }
	fmt.println("Manual entry for all 28 sliders, percent units, range validation, exact values, keyboard, Save and Cancel tests OK")
	return state.errors==0
}

test_crosshair_menu :: proc() -> bool {
	state := menuui.State{page=.SETTINGS, settings_tab=.GAMEPLAY}
	if !menuui.init(&state, menu_test_measure, nil) { return false }
	defer menuui.fini(&state)
	view := menuui.View{crosshair=menuui.DEFAULT_CROSSHAIR_SETTINGS}
	menu_test_frame(&state, view, {})
	for control in menuui.Crosshair_Control {
		menu_test_frame(&state, view, {})
		state.focus = clay.ID(menuui.CROSSHAIR_IDS[control]).id
		before := state.settings_draft.crosshair.values[control]
		menu_test_frame(&state, view, {right=true})
		if abs(state.settings_draft.crosshair.values[control]-min(before+menuui.CROSSHAIR_STEPS[control],menuui.CROSSHAIR_LIMITS[control][1]))>0.001 { fmt.println("Crosshair slider keyboard routing failed",control); return false }
	}
	ids := [menuui.Crosshair_Toggle]string{.CUSTOM_OPACITY="CrosshairCustomOpacity", .ALWAYS_SHOW="CrosshairAlways", .DOT="CrosshairDot"}
	for toggle in menuui.Crosshair_Toggle {
		menu_test_frame(&state, view, {})
		state.focus = clay.ID(ids[toggle],u32(toggle)).id
		before := state.settings_draft.crosshair.toggles[toggle]
		menu_test_frame(&state, view, {enter=true})
		if state.settings_draft.crosshair.toggles[toggle]==before { fmt.println("Crosshair toggle routing failed",toggle); return false }
	}
	for field in 1..=2 {
		menu_test_frame(&state, view, {})
		state.focus = clay.ID("CrosshairColor",u32(field)).id
		menu_test_frame(&state, view, {enter=true})
		menu_test_frame(&state, view, {text="#aB1234"})
		menu_test_frame(&state, view, {enter=true})
		value := field == 1 ? state.settings_draft.crosshair.color : state.settings_draft.crosshair.shadow_color
		if state.color_edit!=0 || value!=0xab1234 { fmt.println("Crosshair hex entry failed"); return false }
	}
	menuui.settings_color_begin(&state,1)
	menu_test_frame(&state,view,{text="invalid"})
	menu_test_frame(&state,view,{enter=true})
	if !state.color_invalid || state.color_edit!=1 || state.settings_draft.crosshair.color!=0xab1234 { fmt.println("Invalid colors must preserve the previous value"); return false }
	menu_test_frame(&state,view,{escape=true})
	if state.page!=.SETTINGS || state.color_edit!=0 { fmt.println("Escape must cancel only the color edit"); return false }
	for control in state.controls[:state.control_count] { if control.id.id==clay.ID("CrosshairType").id { menuui.focus_visible(control,.SETTINGS) } }
	menu_test_frame(&state,view,{})
	menu_test_click(&state,view,clay.ID("CrosshairType"))
	menu_test_frame(&state,view,{})
	if state.settings_dropdown!=.CROSSHAIR_TYPE || state.control_count!=2 || !state.controls[0].enabled || state.controls[1].enabled { fmt.println("Type must offer Precision with Image reserved and disabled"); return false }
	menu_test_frame(&state,view,{tab=true})
	if state.focus!=clay.ID("SettingsOption",0).id { fmt.println("Keyboard navigation must skip Image"); return false }
	menu_test_frame(&state,view,{enter=true})
	if state.settings_dropdown!=.NONE || state.settings_draft.crosshair.kind!=.PRECISION { fmt.println("Precision selection failed"); return false }
	if view.crosshair!=menuui.DEFAULT_CROSSHAIR_SETTINGS { fmt.println("Crosshair edits must remain staged"); return false }
	menu_test_frame(&state,view,{})
	menu_test_frame(&state,view,{escape=true})
	state.page = .SETTINGS
	menu_test_frame(&state,view,{})
	if state.settings_draft.crosshair!=view.crosshair { fmt.println("Cancel must discard every crosshair edit"); return false }
	fmt.println("Precision controls, hex validation, disabled Image dropdown and cancel tests OK")
	return state.errors==0
}

test_settings_scrolling :: proc() -> bool {
	for size in ([3][2]f32{{1280,720},{1920,1080},{2560,1600}}) {
		state := menuui.State{page=.SETTINGS, settings_tab=.GAMEPLAY}
		if !menuui.init(&state, menu_test_measure, nil) { return false }
		defer menuui.fini(&state)
		view := menuui.View{sensitivity=1, visuals=menuui.DEFAULT_VISUAL_SETTINGS}
		menu_test_frame(&state, view, {}, size[0], size[1])
		menu_test_frame(&state, view, {}, size[0], size[1])
		saved_draft := state.settings_draft
		panel := clay.GetElementData(clay.ID("SettingsPanel")).boundingBox
		input := menuui.Input{pointer={panel.x+panel.width/2,panel.y+panel.height/2}, scroll={0,-1}}
		menu_test_frame(&state, view, input, size[0], size[1])
		data := clay.GetScrollContainerData(clay.ID("SettingsPanel"))
		wheel_distance := -data.scrollPosition[1]
		if wheel_distance < 72*state.scale || wheel_distance > 180*state.scale { fmt.println("A wheel notch must move settings by roughly two rows", size, wheel_distance); return false }
		input.scroll = {0,0.5}
		menu_test_frame(&state, view, input, size[0], size[1])
		if abs(data.scrollPosition[1]+wheel_distance/2)>0.01 { fmt.println("Fractional wheel input must remain smooth and reversible"); return false }
		track := clay.GetElementData(clay.ID("SettingsScrollTrack")).boundingBox
		thumb := clay.GetElementData(clay.ID("SettingsScrollThumb")).boundingBox
		if track.width < 14 || thumb.height <= 0 { fmt.println("Scrollbar must have an easy-to-grab thumb", size); return false }
		// An off-center grab must not jump the content. Captured dragging must
		// keep working outside the bar and clamp at both ends.
		before_grab := data.scrollPosition[1]
		input = {pointer={thumb.x+thumb.width/2,thumb.y+thumb.height/4}, down=true}
		menu_test_frame(&state, view, input, size[0], size[1])
		if !state.scrollbar_dragging || abs(data.scrollPosition[1]-before_grab)>0.01 { fmt.println("Grabbing the thumb must preserve its position"); return false }
		input.pointer = {track.x-300,track.y+track.height+200}
		menu_test_frame(&state, view, input, size[0], size[1])
		span := data.contentDimensions.height-data.scrollContainerDimensions.height
		if abs(data.scrollPosition[1]+span)>0.01 { fmt.println("Dragging below the bar must reach the bottom"); return false }
		// Releasing over Save must finish the drag without clicking Save.
		save := clay.GetElementData(clay.ID("SettingsSave")).boundingBox
		input = {pointer={save.x+save.width/2,save.y+save.height/2}}
		action := menu_test_frame(&state, view, input, size[0], size[1])
		if state.scrollbar_dragging || action.kind != .NONE || state.page != .SETTINGS { fmt.println("Scrollbar release must not activate underlying settings controls"); return false }
		thumb = clay.GetElementData(clay.ID("SettingsScrollThumb")).boundingBox
		input = {pointer={thumb.x+thumb.width/2,thumb.y+thumb.height/4}, down=true}
		menu_test_frame(&state, view, input, size[0], size[1])
		input.pointer = {track.x+300,track.y-200}
		menu_test_frame(&state, view, input, size[0], size[1])
		if abs(data.scrollPosition[1])>0.01 { fmt.println("Dragging above the bar must reach the top"); return false }
		input.pointer = {track.x,track.y+(track.height-thumb.height)/2+thumb.height/4}
		menu_test_frame(&state, view, input, size[0], size[1])
		if abs(data.scrollPosition[1]+span/2)>0.1 { fmt.println("Dragging to the middle must scroll proportionally"); return false }
		input.down = false
		menu_test_frame(&state, view, input, size[0], size[1])
		input = {pointer={track.x+track.width/2,track.y+track.height-1}, down=true}
		menu_test_frame(&state, view, input, size[0], size[1])
		if !state.scrollbar_dragging || abs(data.scrollPosition[1]+span)>0.01 { fmt.println("Clicking the empty track must jump toward the click"); return false }
		input.down = false
		menu_test_frame(&state, view, input, size[0], size[1])
		// Wheel scrolling over the bar itself must still reach the panel.
		input.scroll = {0,1}
		menu_test_frame(&state, view, input, size[0], size[1])
		if data.scrollPosition[1] <= -span+1 { fmt.println("The scrollbar must accept wheel input as well as dragging"); return false }
		if state.settings_draft != saved_draft { fmt.println("Scrollbar interactions must never edit settings"); return false }
		input.scroll, input.down = {}, true
		menu_test_frame(&state, view, input, size[0], size[1])
		input.escape = true
		menu_test_frame(&state, view, input, size[0], size[1])
		if state.page != .HOME || state.scrollbar_dragging { fmt.println("Escape during a scrollbar drag must cancel the capture and settings"); return false }
		// A short tab must have neither a scrollbar nor a stale capture.
		state.page, state.settings_tab = .SETTINGS, .AUDIO
		menu_test_frame(&state, view, {}, size[0], size[1])
		menu_test_frame(&state, view, {}, size[0], size[1])
		if clay.GetElementData(clay.ID("SettingsScrollTrack")).found || state.scrollbar_dragging { fmt.println("A non-scrolling tab must not retain a scrollbar"); return false }
	}
	fmt.println("Fast wheel scrolling, fractional input, draggable scrollbar, track jumps and capture tests OK")
	return true
}

test_graphics_menu :: proc() -> bool {
	state := menuui.State{page=.SETTINGS}
	if !menuui.init(&state, menu_test_measure, nil) { return false }
	defer menuui.fini(&state)
	view := menuui.View{visuals=menuui.DEFAULT_VISUAL_SETTINGS, max_anisotropy=4, sensitivity=1}
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("SettingsTab", u32(menuui.Settings_Tab.GAMEPLAY)))
	menu_test_frame(&state, view, {})
	if state.settings_tab != .GAMEPLAY || state.control_count != len(menuui.Settings_Tab)+9+2*len(menuui.Viewmodel_Control)+len(menuui.Viewmodel_Toggle)+2*len(menuui.Crosshair_Control)+len(menuui.Crosshair_Toggle) { fmt.println("Gameplay must expose global viewmodel, trails and crosshair controls with editable numbers"); return false }
	state.focus = clay.ID("FieldOfView").id
	menu_test_frame(&state, view, {right=true})
	if state.settings_draft.fov != 95 { fmt.println("FOV keyboard adjustment must start from the current draft angle"); return false }
	for control in menuui.Viewmodel_Control {
		menu_test_frame(&state, view, {})
		state.focus = clay.ID(menuui.VIEWMODEL_IDS[control]).id
		before := state.settings_draft.viewmodel.values[control]
		menu_test_frame(&state, view, {right=true})
		step: f32 = control == .WEAPON_FOV ? 5 : 0.1
		if abs(state.settings_draft.viewmodel.values[control]-min(before+step, menuui.VIEWMODEL_LIMITS[control][1]))>0.001 { fmt.println("Viewmodel slider keyboard routing failed", control); return false }
	}
	for toggle in menuui.Viewmodel_Toggle {
		menu_test_frame(&state, view, {})
		state.focus = clay.ID(menuui.VIEWMODEL_TOGGLE_IDS[toggle], u32(toggle)).id
		before := state.settings_draft.viewmodel.toggles[toggle]
		menu_test_frame(&state, view, {enter=true})
		if state.settings_draft.viewmodel.toggles[toggle] == before { fmt.println("Viewmodel toggle routing failed", toggle); return false }
	}
	state.focus = clay.ID("BulletTrails").id
	menu_test_frame(&state, view, {})
	menu_test_frame(&state, view, {enter=true})
	if !state.settings_draft.trails.hide_others || state.settings_draft.trails.hide_yours { fmt.println("Bullet trails must only toggle other players' trails"); return false }
	state.focus = clay.ID("YourTrails", 1).id
	menu_test_frame(&state, view, {})
	menu_test_frame(&state, view, {enter=true})
	if !state.settings_draft.trails.hide_others || !state.settings_draft.trails.hide_yours { fmt.println("Your trails must independently toggle local trails"); return false }
	for control in state.controls[:state.control_count] { if control.id.id == clay.ID("CrosshairDot", u32(menuui.Crosshair_Toggle.DOT)).id { menuui.focus_visible(control, .SETTINGS) } }
	menu_test_frame(&state, view, {})
	last_box := clay.GetElementData(clay.ID("CrosshairDot", u32(menuui.Crosshair_Toggle.DOT))).boundingBox
	viewmodel_panel := clay.GetElementData(clay.ID("SettingsPanel")).boundingBox
	if last_box.y < viewmodel_panel.y-1 || last_box.y+last_box.height > viewmodel_panel.y+viewmodel_panel.height+1 { fmt.println("Last Gameplay control must scroll fully into view"); return false }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("SettingsTab", u32(menuui.Settings_Tab.VISUALS)))
	menu_test_frame(&state, view, {})
	state.focus = clay.ID("Visual1").id // Gamma.
	menu_test_frame(&state, view, {right=true})
	if abs(state.settings_draft.visuals.values[.GAMMA]-1.05)>0.001 || view.visuals.values[.GAMMA] != 1 { fmt.println("Visual sliders must stage changes from their own value"); return false }
	menu_test_frame(&state, view, {})
	if clay.GetElementData(clay.ID("Visual6")).found || clay.GetElementData(clay.ID("VisualOverride0")).found || clay.GetElementData(clay.ID("VisualColor0_0")).found { fmt.println("Fog distance and color overrides must not be editable in Settings"); return false }
	// Both map-detail toggles must be reachable and stage changes independently.
	state.focus = clay.ID("Visual5Value").id
	menu_test_frame(&state, view, {tab=true})
	menu_test_frame(&state, view, {})
	if state.focus != clay.ID("HideCats").id { fmt.println("Hide cats must be reachable after lighting"); return false }
	menu_test_frame(&state, view, {enter=true})
	menu_test_frame(&state, view, {})
	menu_test_frame(&state, view, {tab=true})
	menu_test_frame(&state, view, {})
	if state.focus != clay.ID("HideExtraProps", 1).id { fmt.println("Hide extra props must be independently reachable"); return false }
	menu_test_frame(&state, view, {enter=true})
	menu_test_frame(&state, view, {})
	if !state.settings_draft.visuals.hide_cats || !state.settings_draft.visuals.hide_extra_props || view.visuals.hide_cats || view.visuals.hide_extra_props { fmt.println("Map detail toggles must stage changes without modifying saved preferences"); return false }
	menu_test_frame(&state, view, {tab=true})
	menu_test_frame(&state, view, {})
	box := clay.GetElementData(clay.ID("ResetVisuals")).boundingBox
	panel := clay.GetElementData(clay.ID("SettingsPanel")).boundingBox
	if state.focus != clay.ID("ResetVisuals").id || box.y < panel.y-1 || box.y+box.height > panel.y+panel.height+1 { fmt.println("Reset visuals must remain reachable by keyboard"); return false }
	menu_test_click(&state, view, clay.ID("SettingsTab", u32(menuui.Settings_Tab.VIDEO)))
	menu_test_frame(&state, view, {})
	for control in state.controls[:state.control_count] { if control.id.id == clay.ID("TextureFiltering").id { menuui.focus_visible(control, .SETTINGS) } }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("TextureFiltering"))
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("SettingsOption", 1))
	menu_test_frame(&state, view, {})
	for control in state.controls[:state.control_count] { if control.id.id == clay.ID("Anisotropy").id { menuui.focus_visible(control, .SETTINGS) } }
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("Anisotropy"))
	menu_test_frame(&state, view, {})
	if state.control_count != 3 { fmt.println("Anisotropic filtering must list only supported levels"); return false }
	menu_test_click(&state, view, clay.ID("SettingsOption", 2))
	menu_test_frame(&state, view, {})
	value := menu_test_click(&state, view, clay.ID("SettingsSave"))
	if value.kind != .SETTINGS_SAVE || !state.settings_draft.quality.smooth_textures || state.settings_draft.quality.anisotropy != 4 || abs(state.settings_draft.visuals.values[.GAMMA]-1.05)>0.001 { fmt.println("Graphics changes must survive tab switches and Save"); return false }
	fmt.println("Visuals, Gameplay FOV, graphics scrolling, supported quality choices and staging tests OK")
	return true
}

test_standard_menu :: proc() -> bool {
	state: menuui.State
	if !menuui.init(&state, menu_test_measure, nil) { return false }
	defer menuui.fini(&state)
	classes: [len(shared.CLASSES_LIST)]menuui.Class
	for class, i in shared.CLASSES_LIST { classes[i] = {id=i32(i), name=class.name, weapon="Primary weapon", available=true} }
	classes[1].available = false
	classes[1].reason = "Restricted by this server"
	view := menuui.View{classes=classes[:], online=true, ready=true, selected_class=2, confirmed_class=0,
		map_name="Sandstorm", mode="Hardpoint", lobby_name="Standard lobby", resolution="1920 x 1080", sensitivity=1,
		teams={{id=1,name="An exceptionally long Alpha team name",capacity=4,available=true},{id=2,name="Bravo",capacity=4,available=true}}}
	for size in ([?][2]f32{{1280,720},{1920,1080},{2560,1600}}) {
		for manual in ([?]bool{false,true}) {
			view.team_selection = manual
			for page in menuui.Page {
				state.page = page
				menu_test_frame(&state, view, {}, size[0], size[1])
				if state.errors != 0 { fmt.eprintln("Standard menu layout failed"); return false }
				for id in ([?]string{"StandardPlayPanel","SelectedClass","Play","ChangeClass"}) {
					data := clay.GetElementData(clay.ID(id, id == "ChangeClass" ? u32(menuui.Page.CLASSES) : 0)); box := data.boundingBox
					if !data.found || box.width <= 0 || box.height <= 0 || box.x < 0 || box.y < 0 || box.x+box.width > size[0]+1 || box.y+box.height > size[1]+1 {
						fmt.println("Standard menu bounds failed", id, size, box); return false
					}
				}
			}
		}
	}
	state.page = .HOME
	view.team_selection = false
	menu_test_frame(&state, view, {})
	for control in state.controls[:state.control_count] {
		if control.action.kind == .SELECT_CLASS || control.action.kind == .SELECT_TEAM { fmt.println("Unexpected standard menu selection control"); return false }
	}
	if menu_test_click(&state, view, clay.ID("Play")).kind != .PLAY { fmt.println("Standard Play failed"); return false }
	menu_test_click(&state, view, clay.ID("ChangeClass",u32(menuui.Page.CLASSES)))
	if state.page != .CLASSES { fmt.println("Change class navigation failed"); return false }
	menu_test_frame(&state, view, {})
	// A locked class stays focusable and does not close the picker.
	if menu_test_click(&state, view, clay.ID("ClassChoice",1)).kind != .NONE || state.page != .CLASSES { fmt.println("Restricted class navigation failed"); return false }
	if menu_test_click(&state, view, clay.ID("Play")).kind == .PLAY { fmt.println("Play activated through class picker"); return false }
	choice := menu_test_click(&state, view, clay.ID("ClassChoice",2))
	if choice.kind != .SELECT_CLASS || choice.index != 2 { fmt.println("Class picker selection failed", choice); return false }
	// Scrolling via Tab must reach the last row of portraits.
	state.focus = clay.ID("Back").id
	for _ in 0..<len(classes) { menu_test_frame(&state, view, {}); menu_test_frame(&state, view, {tab=true}) }
	scroll := clay.GetScrollContainerData(clay.ID("ClassPicker"))
	if !scroll.found || scroll.scrollPosition[1] >= 0 { fmt.println("Class picker focus did not scroll"); return false }
	view.active = true
	if menu_test_frame(&state, view, {escape=true}).kind != .NONE || state.page != .HOME || state.focus != clay.ID("ChangeClass",u32(menuui.Page.CLASSES)).id { return false }
	menu_test_frame(&state, view, {})
	if menu_test_frame(&state, view, {escape=true}).kind != .PLAY { return false }
	view.active = false
	view.team_selection = true
	view.play_reason = "Choose a team to enter game"
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("Play")).kind != .NONE { return false }
	if menu_test_click(&state, view, clay.ID("JoinTeam",2)).index != 2 { return false }
	view.team_pending = true; view.requested_team = 2
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("JoinTeam",2)).kind != .NONE || view.confirmed_team != 0 { return false }
	view.team_pending = false; view.confirmed_team = 2; view.play_reason = ""
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("JoinTeam",0)).kind != .SELECT_TEAM { return false }
	fmt.println("Standard lobby, class overlay, keyboard scrolling and team confirmation tests OK")
	return true
}

test_lobby_packets :: proc() -> bool {
	state := shared.Lobby_State{local_id=42, team=1, capacity=4, select_team=true, team_result=2, team_names={"Alpha with a long team name", "Bravo"}, count=shared.MAX_PLAYERS_PER_MATCH}
	for &player, i in state.players { player = {id=u32(i+1), team=i32(i%2+1), class_id=i32(i%4)} }
	buffer: [512]byte
	size := shared.packet_serialize_lobby(buffer[:], &state)
	decoded, ok := shared.packet_deserialize_lobby(buffer[:size])
	if !ok || decoded.count != state.count || decoded.local_id != 42 || decoded.team_result != 2 || decoded.team_names != state.team_names || decoded.players != state.players { return false }
	for end in 0..<size {
		if _, valid := shared.packet_deserialize_lobby(buffer[:end]); valid { return false }
	}
	size = shared.packet_serialize_team_request(buffer[:], 2)
	team, valid := shared.packet_deserialize_team_request(buffer[:size])
	if !valid || team != 2 { return false }
	size = shared.packet_serialize_team_request(buffer[:], 3)
	if _, accepted := shared.packet_deserialize_team_request(buffer[:size]); accepted { return false }
	fmt.println("Lobby roster and team request protocol tests OK")
	return true
}


test_live_lobby_records :: proc() -> bool {
	world: kproto.Krunker_World_State
	defer kproto.krunker_world_reset(&world)
	init_packet: [18]kproto.Krunker_Msgpack_Value
	init_packet[0], init_packet[1], init_packet[2] = "init", i64(2), i64(2)
	init_packet[16], init_packet[17] = true, true
	if !kproto.krunker_world_apply_init(&world, init_packet[:]) || !world.is_comp || !world.is_ranked { return false }
	if !kproto.krunker_world_apply_init(&world, init_packet[:3]) || world.is_comp || world.is_ranked { return false }
	world.local_socket_id = ""
	record := []kproto.Krunker_Msgpack_Map_Entry{{key="n",value="Player name"},{key="t",value=i64(1)},{key="c",value=i64(2)},{key="a",value=false}}
	roster := []kproto.Krunker_Msgpack_Map_Entry{{key="socket-a",value=record}}
	if !kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"cd",roster}) { return false }
	if len(world.lobby_players)!=1 || world.lobby_players[0].team!=1 || world.lobby_players[0].name!="Player name" || world.lobby_players[0].class_index!=2 { return false }
	change := []kproto.Krunker_Msgpack_Map_Entry{{key="n",value="Player name"},{key="t",value=i64(2)},{key="a",value=true}}
	if !kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"cda","socket-a",change}) { return false }
	if world.lobby_players[0].team!=2 || world.lobby_players[0].name!="Player name" || world.lobby_players[0].class_index != -1 { return false }
	if !kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"cda","socket-a",kproto.Krunker_Msgpack_Nil{}}) || len(world.lobby_players) != 0 { return false }
	fmt.println("Live pre-spawn lobby roster and assignment tests OK")
	return true
}
