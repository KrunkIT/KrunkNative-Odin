package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import menuui "../menu"
import clay "../third_party/clay"
import shared "../shared"

when ODIN_TEST {
	@(test)
	menu_typography :: proc(t: ^testing.T) {
		// The C text-measure callback uses the default allocator for glyphs.
		// Keep font loading and cleanup on that same allocator in this test.
		logger := context.logger
		context = runtime.default_context()
		context.logger = logger
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(1600, 900, "Menu typography", nil, nil)
		if !testing.expect(t, window != nil, "hidden OpenGL window failed") do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		ui := ui_init()
		defer { ui_fini(ui); resource_cache_fini() }
		state: menuui.State
		if !testing.expect(t, menuui.init(&state, menu_measure_text, ui), "menu initialization failed") do return
		defer menuui.fini(&state)
		classes: [len(shared.CLASSES_LIST)]menuui.Class
		for class, i in shared.CLASSES_LIST {
			path := shared.concat(shared.assets_path(), fmt.tprintf("textures/classes/icon_%d.png", class.icon_index))
			texture := load_texture(path); delete(path)
			classes[i] = {id=i32(i), name=class.name, weapon="Primary weapon", available=shared.class_is_in_rotation(i32(i)), portrait=rawptr(uintptr(texture)), reason="Restricted by lobby rules"}
			classes[i].health, classes[i].wall_jump = class.health, class.wall_jump
			if len(class.loadout) > 0 {
				weapon := shared.WEAPONS_LIST[class.loadout[0]]
				folder := weapon.melee ? "melee" : "weapons"
				path = shared.concat(shared.assets_path(), fmt.tprintf("textures/%s/%s.png", folder, weapon.icon))
				classes[i].weapon_icon = rawptr(uintptr(load_texture(path))); delete(path)
				classes[i].weapon = weapon.name
			}
		}
		classes[2].weapon="SMG"
		secondaries := make([dynamic]menuui.Secondary)
		defer delete(secondaries)
		for weapon, id in shared.WEAPONS_LIST {
			if weapon == nil || !weapon.secondary || weapon.melee { continue }
			path := shared.concat(shared.assets_path(), fmt.tprintf("textures/weapons/%s.png", weapon.icon))
			texture := load_texture(path); delete(path)
			append(&secondaries, menuui.Secondary{id=i32(id),name=weapon.name,icon=rawptr(uintptr(texture))})
		}
		selected_name := classes[2].name
		classes[1].used=1; classes[1].limit=1
		players := [?]menuui.Player{
			{name="An exceptionally long competitive player name",class_name="Run N Gun",team=1,is_you=true},
			{name="Northstar",class_name="Hunter",team=1},
			{name="Arc",class_name="Triggerman",team=1},
			{name="Marble",class_name="Vince",team=1},
			{name="Rival",class_name="Hunter",team=2},
		}
		view := menuui.View{classes=classes[:],players=players[:],online=true,ready=true,selected_class=2,confirmed_class=0,confirmed_team=1,map_name="Sandstorm",mode="Hardpoint",lobby_name="EU competitive / A1B2",match_status="Waiting for players",resolution="1920 x 1080",sensitivity=1,
			teams={{id=1,name="Alpha",capacity=4,available=true,score=42},{id=2,name="Bravo",capacity=4,available=true,score=38}}}
		view.presentation = .COMPETITIVE
		view.bindings = menuui.default_bindings()
		view.audio_volumes = {0.8, 1, 0.8, 0.6}
		view.resolution_options = []string{"1280 x 720", "1600 x 900", "1920 x 1080", "2560 x 1440"}
		view.monitor_names = []string{"Primary monitor", "Second monitor with a long name"}
		view.visuals = menuui.DEFAULT_VISUAL_SETTINGS
		view.max_anisotropy = 16
		view.secondaries = secondaries[:]
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		sizes := [?][2]i32{{1280,720}, {1920,1080}, {2560,1600}}
		for size in sizes {
			glfw.SetWindowSize(window, size[0], size[1])
			glfw.PollEvents()
			gl.Viewport(0, 0, size[0], size[1])
			ui_update(ui, f32(size[0]), f32(size[1]))
			full_players: [32]menuui.Player
			for &player, i in full_players { player = {name="Competitive player with a long name", class_name="Run N Gun", team=i32(i%2+1), is_you=i==0} }
			play_y: f32
			for scenario in 0..<46 {
				view.online=true; view.team_pending=false; view.class_pending=false; view.spawn_pending=false; view.join_status=""; view.active=false
				view.presentation=.COMPETITIVE; view.ranked=false; view.team_selection=false; view.local_practice=false; view.ready=true; view.confirmed_team=1; view.play_reason=""
				view.teams[0].name="Alpha"; view.teams[1].name="Bravo"
				classes[2].name=selected_name; classes[2].weapon="SMG"
				for &class in classes { class.available = shared.class_is_in_rotation(class.id) }
				state.page=.HOME
				state.settings_dropdown=.NONE; state.binding_capture=0
				state.color_edit=0; state.color_invalid=false
				state.number_edit=.NONE; state.number_invalid=false
				view.visuals = menuui.DEFAULT_VISUAL_SETTINGS
				view.advanced_sensitivity = false
				view.players=players[:]; view.teams[0].capacity=4; view.teams[1].capacity=4; view.selection_status=""
				view.secondary_name="Pistol"; view.selected_secondary=2; view.secondary_reason=""; view.secondary_pending=false
				view.respawn_remaining=0
				view.selected_class=2; state.loadout_parent=.CLASSES; state.loadout_return_focus=clay.ID("ClassChoice",0).id
				switch scenario {
				case 0:
				case 1: view.team_pending=true; view.requested_team=2; view.class_pending=true; view.spawn_pending=true; view.selection_status="Awaiting server confirmation"
				case 2: state.page=.SETTINGS; state.settings_tab=.MAIN
				case 3: state.page=.SESSION; menuui.set_invite(&state,"https://krunker.io/?game=FRA:long-invite-code")
				case 4: view.online=false; view.join_status="Connection failed. Check your invite and try again."; menuui.set_invite(&state,"")
				case 5: view.active=true
				case 6: state.page=.CONTROLS
				case 7: view.players=full_players[:]; view.teams[0].capacity=16; view.teams[1].capacity=16
				case 8: view.presentation=.STANDARD
				case 9: view.presentation=.STANDARD; view.team_selection=true; view.confirmed_team=0; view.play_reason="Choose a team to enter game"; view.teams[0].name="An exceptionally long Alpha team name"; classes[2].name="An exceptionally long selected class name"; classes[2].weapon="An exceptionally long primary weapon name"
				case 10: view.presentation=.STANDARD; view.team_selection=true; view.team_pending=true; view.requested_team=2; view.selection_status="Waiting for the server to confirm your team"
				case 11: view.presentation=.STANDARD; view.active=true
				case 12: view.presentation=.STANDARD; state.page=.CLASSES
				case 13: view.presentation=.STANDARD; state.page=.CLASSES; view.selection_status="Could not send class selection. Please try again."; state.focus=clay.ID("ClassChoice",4).id
				case 14: view.presentation=.STANDARD; state.page=.SETTINGS; state.settings_tab=.MAIN
				case 15: view.presentation=.STANDARD; view.online=false; view.local_practice=true; view.team_selection=true
				case 16: view.presentation=.STANDARD; view.ready=false
				case 17: view.ranked=true
				case 18: view.presentation=.STANDARD; state.page=.LOADOUT; view.selected_class=0; view.selected_secondary=15; view.secondary_name="Sawed Off"
				case 19: view.presentation=.STANDARD; state.page=.LOADOUT; view.selected_class=0; view.active=true; view.secondary_pending=true; view.selection_status="Could not send secondary selection. Please try again."
				case 20: view.presentation=.STANDARD; state.page=.LOADOUT; view.secondary_reason="This class has no secondary weapon"; view.secondary_name="None"
				case 21: state.page=.LOADOUT; view.selected_class=0; state.loadout_parent=.HOME
				case 22: view.presentation=.STANDARD; state.page=.LOADOUT; view.selected_class=0; view.secondary_reason="Secondaries are disabled in this lobby"; view.secondary_name="None"
				case 24,25,26,27:
					view.players = []menuui.Player{players[0], players[4]}
					view.teams[0].capacity, view.teams[1].capacity = scenario-23, scenario-23
				case 28: view.respawn_remaining=2.4; view.has_life=true
				case 29: state.page=.CLASSES; view.ranked=true
				case 30: for &class in classes { class.available=true }
				case 31: for &class in classes { class.available=false }
				case 32: state.page=.SETTINGS; state.settings_tab=.VIDEO
				case 33: state.page=.SETTINGS; state.settings_tab=.AUDIO
				case 34: state.page=.SETTINGS; state.settings_tab=.HUD
				case 35: state.page=.SETTINGS; state.settings_tab=.VIDEO; state.settings_dropdown=.DISPLAY_MODE; state.focus=clay.ID("SettingsOption",1).id
				case 36: state.page=.SETTINGS; state.settings_tab=.INPUT; state.binding_capture=1
				case 37: state.page=.SETTINGS; state.settings_tab=.VISUALS
				case 38:
					state.page=.SETTINGS; state.settings_tab=.VISUALS; state.settings_active=false
					for group in menuui.Visual_Color { view.visuals.color_override[group]=true }
				case 39: state.page=.SETTINGS; state.settings_tab=.GAMEPLAY
				case 40: state.page=.SETTINGS; state.settings_tab=.VIDEO
				case 41: state.page=.SETTINGS; state.settings_tab=.MAIN; state.settings_active=false; view.advanced_sensitivity=true
				case 42: state.page=.SETTINGS; state.settings_tab=.GAMEPLAY
				case 43,44: state.page=.SETTINGS; state.settings_tab=.GAMEPLAY
				case 45: state.page=.SETTINGS; state.settings_tab=.GAMEPLAY; state.settings_active=false
				case 23: view.presentation=.STANDARD; state.page=.LOADOUT; classes[2].name="An exceptionally long selected class name"; classes[2].weapon="An exceptionally long primary weapon name"
				}
				page := state.page
				commands := menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
				if scenario == 42 {
					for control in state.controls[:state.control_count] { if control.id.id == clay.ID("CrosshairDot", u32(menuui.Crosshair_Toggle.DOT)).id { menuui.focus_visible(control, .SETTINGS) } }
					commands = menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
					box := clay.GetElementData(clay.ID("CrosshairDot", u32(menuui.Crosshair_Toggle.DOT))).boundingBox
					panel := clay.GetElementData(clay.ID("SettingsPanel")).boundingBox
						testing.expect(t, box.y >= panel.y-1 && box.y+box.height <= panel.y+panel.height+1, "the final Gameplay control must remain reachable at every viewport size")
				}
				if scenario == 43 || scenario == 44 {
					target := scenario == 43 ? clay.ID("CrosshairType") : clay.ID("CrosshairColor", 1)
					for control in state.controls[:state.control_count] { if control.id.id == target.id { menuui.focus_visible(control, .SETTINGS) } }
					commands = menuui.build(&state, view, {}, ui.width, ui.height, 1.0/60.0)
					if scenario == 43 { menuui.activate(&state, {id=target, action={kind=.SETTINGS_DROPDOWN, index=i32(menuui.Settings_Dropdown.CROSSHAIR_TYPE)}}) }
					if scenario == 44 {
						menuui.settings_color_begin(&state, 1)
						state.settings_draft.crosshair.values[.THICKNESS], state.settings_draft.crosshair.values[.SIZE], state.settings_draft.crosshair.values[.GAP] = 100, 100, -100
					}
					commands = menuui.build(&state, view, {}, ui.width, ui.height, 1.0/60.0)
				}
				if state.page == .SETTINGS && state.settings_tab == .GAMEPLAY {
					box := clay.GetElementData(clay.ID("CrosshairPreview")).boundingBox
					sidebar := clay.GetElementData(clay.ID("SettingsSidebar")).boundingBox
					testing.expect(t, box.width>0 && box.height>0 && box.x>=sidebar.x && box.y>=sidebar.y && box.x+box.width<=sidebar.x+sidebar.width+1 && box.y+box.height<=sidebar.y+sidebar.height+1, "the crosshair preview must stay visible in the sidebar while scrolling")
				}
				if scenario == 45 {
					for control in state.controls[:state.control_count] {
						if control.id.id != clay.ID("CrosshairGapValue").id { continue }
						menuui.focus_visible(control, .SETTINGS)
						menuui.activate(&state, control)
						break
					}
					state.previous = {}
					menuui.interact(&state, {text="-3.125"}, view)
					commands = menuui.build(&state, view, {}, ui.width, ui.height, 1.0/60.0)
				}
				if scenario == 40 {
					for control in state.controls[:state.control_count] {
						if control.id.id == clay.ID("Anisotropy").id { menuui.focus_visible(control, .SETTINGS) }
					}
					commands = menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
					menuui.activate(&state, {id=clay.ID("Anisotropy"), action={kind=.SETTINGS_DROPDOWN, index=i32(menuui.Settings_Dropdown.ANISOTROPY)}})
					commands = menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
				}
				if scenario == 21 {
					// The final secondary must remain reachable in the loadout grid.
					state.focus = clay.ID("SecondaryChoice", 16).id
					state.previous = {}
					menuui.interact(&state, {tab = true}, view)
					commands = menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
					box := clay.GetElementData(clay.ID("SecondaryChoice", 21)).boundingBox
					parent := clay.GetElementData(clay.ID("SecondaryPicker")).boundingBox
					testing.expect(t, state.focus == clay.ID("SecondaryChoice", 21).id && box.height > 0 &&
						box.y >= parent.y-1 && box.y+box.height <= parent.y+parent.height+1,
						"Techy-9 must scroll fully into view on keyboard focus")
					action := menuui.interact(&state, {enter = true}, view)
					testing.expect(t, action.kind == .SELECT_SECONDARY && action.index == 21,
						"Techy-9 must remain selectable separately from Auto Pistol")
				}
				testing.expect(t, state.errors == 0, "menu layout reported an error")
				if page == .SETTINGS || page == .CONTROLS {
					overlay := clay.GetElementData(clay.ID("Overlay")).boundingBox
					for id in ([]string{"SettingsSidebar", "SettingsHeading", "SettingsPanel", "SettingsFooter", "SettingsSave", "SettingsCancel"}) {
						box := clay.GetElementData(clay.ID(id)).boundingBox
						testing.expectf(t, box.width > 0 && box.height > 0 && box.x >= overlay.x-1 && box.y >= overlay.y-1 && box.x+box.width <= overlay.x+overlay.width+1 && box.y+box.height <= overlay.y+overlay.height+1,
							"settings section %s must fit at %v", id, size)
					}
					for control in state.controls[:state.control_count] {
						box := clay.GetElementData(control.id).boundingBox
						if control.action.kind == .BIND_KEY {
							testing.expect(t, box.width > 200*state.scale && box.height >= 44*state.scale && box.x >= overlay.x && box.x+box.width <= overlay.x+overlay.width,
								"both binding columns must fit horizontally and remain large enough to click")
							continue // The full action list scrolls vertically.
						}
						if state.settings_dropdown == .NONE && (state.settings_tab == .VISUALS || state.settings_tab == .VIDEO || state.settings_tab == .MAIN || state.settings_tab == .GAMEPLAY) && control.action.kind != .SETTINGS_TAB && control.action.kind != .SETTINGS_SAVE && control.action.kind != .SETTINGS_CANCEL {
							testing.expect(t, box.width > 0 && box.height > 0 && box.x >= overlay.x-1 && box.x+box.width <= overlay.x+overlay.width+1, "scrolling settings must fit horizontally")
							continue
						}
						testing.expectf(t, box.width > 0 && box.height > 0 && box.x >= overlay.x-1 && box.y >= overlay.y-1 && box.x+box.width <= overlay.x+overlay.width+1 && box.y+box.height <= overlay.y+overlay.height+1,
							"settings controls must remain accessible at %v", size)
					}
					if state.settings_tab == .MAIN || state.settings_tab == .AUDIO {
						name := "MasterVolume"
						track := clay.GetElementData(clay.ID(name)).boundingBox
						thumb := clay.GetElementData(clay.ID(fmt.tprintf("%sThumb", name))).boundingBox
						testing.expect(t, thumb.height > track.height*0.5 && thumb.y >= track.y && thumb.y+thumb.height <= track.y+track.height,
							"sliders need a visible thumb centered inside the interactive track")
					}
				}
				if view.presentation == .COMPETITIVE && (page == .HOME || page == .CLASSES) && view.online {
					prefix := page == .HOME ? "Class" : "ClassChoice"
					parent := clay.GetElementData(clay.ID(page == .HOME ? "ClassStrip" : "ClassPicker")).boundingBox
					for class in classes {
						data := clay.GetElementData(clay.ID(prefix, u32(class.id)))
						if !class.available {
							testing.expect(t, !data.found, "competitive pickers must omit excluded classes completely")
							for control in state.controls[:state.control_count] {
								if control.action.kind == .SELECT_CLASS || control.action.kind == .INSPECT_CLASS { testing.expect(t, control.action.index != class.id) }
							}
							continue
						}
						box := data.boundingBox
						testing.expect(t, data.found && box.width <= 112*state.scale+1 && box.height <= 112*state.scale+1 &&
							box.x>=parent.x-1 && box.x+box.width<=parent.x+parent.width+1 && box.y>=parent.y-1 && box.y+box.height<=parent.y+parent.height+1,
							"all allowed competitive class tiles must fit within the compact selector")
					}
				}
				if page == .LOADOUT {
					for id in ([?]string{"ClassLoadout", "LoadoutClass", "LoadoutPrimary", "LoadoutStatus"}) {
						box := clay.GetElementData(clay.ID(id)).boundingBox
						testing.expect(t, box.width>0 && box.height>0 && box.x>=0 && box.y>=0 && box.x+box.width<=ui.width+1 && box.y+box.height<=ui.height+1,
							"class loadout sections must stay within the viewport")
					}
					if len(view.secondary_reason) > 0 {
						for control in state.controls[:state.control_count] {
							testing.expect(t, control.action.kind != .SELECT_SECONDARY, "restricted classes must explain the empty secondary slot without offering invalid choices")
						}
					}
				}
				gl.ClearColor(0.17, 0.17, 0.17, 1)
				gl.Clear(gl.COLOR_BUFFER_BIT)
				menu_render_commands(ui, commands)
				if page == .SETTINGS && state.settings_tab == .GAMEPLAY {
					box := clay.GetElementData(clay.ID("CrosshairPreview")).boundingBox
					pixel: [3]u8
					gl.ReadPixels(i32(box.x+box.width*0.5), size[1]-1-i32(box.y+box.height*0.5), 1, 1, gl.RGB, gl.UNSIGNED_BYTE, &pixel[0])
					testing.expectf(t, pixel[0]>240 && pixel[1]>240 && pixel[2]>240, "the Precision reticle must actually render in the preview at %v (scenario %d)", size, scenario)
					if scenario == 44 {
						gl.ReadPixels(i32(box.x-4), size[1]-1-i32(box.y+box.height*0.5), 1, 1, gl.RGB, gl.UNSIGNED_BYTE, &pixel[0])
						testing.expect(t, pixel[0]<100 && pixel[1]<100 && pixel[2]<100, "extreme crosshair sizes must stay clipped to the preview")
					}
				}
				labels := [?][2]string{
					{"Quit", "Quit"}, {"Enter Game", "Play"}, {"Respawn", "Play"}, {"Resume", "Play"}, {"Join", "JoinLink"}, {"Paste", "Paste"},
					{"Change class", "ChangeClass"}, {"Done", "LoadoutDone"},
					{"Save", "SettingsSave"}, {"Cancel", "SettingsCancel"},
				}
				for command in commands.internalArray[:commands.length] {
					if command.commandType != .Text { continue }
					text := command.renderData.text.stringContents
					if scenario == 45 && string(text.chars[:text.length]) == "-3.125|" {
						box := clay.GetElementData(clay.ID("CrosshairGapValue")).boundingBox
						bounds := command.boundingBox
						testing.expect(t, bounds.x>=box.x && bounds.x+bounds.width<=box.x+box.width && bounds.y>=box.y && bounds.y+bounds.height<=box.y+box.height, "the editable number and caret must fit inside the value field at every resolution")
					}
					testing.expect(t, string(text.chars[:text.length]) != "Change secondary", "the lobby must not have a separate secondary button")
					for label in labels {
						if string(text.chars[:text.length]) != label[0] { continue }
						index := label[1] == "ChangeClass" ? u32(menuui.Page.CLASSES) : 0
						parent := clay.GetElementData(clay.ID(label[1], index))
						box := command.boundingBox
						testing.expect(t, parent.found && box.x >= parent.boundingBox.x && box.y >= parent.boundingBox.y &&
							box.x + box.width <= parent.boundingBox.x + parent.boundingBox.width &&
							box.y + box.height <= parent.boundingBox.y + parent.boundingBox.height,
							"actual font label must fit inside its button")
					}
					if page == .CLASSES && command.zIndex == 10 {
						label := string(text.chars[:text.length])
						for class in classes {
							if label != class.name { continue }
							parent := clay.GetElementData(clay.ID("ClassChoiceName", u32(class.id))).boundingBox
							box := command.boundingBox
							testing.expect(t, box.x>=parent.x && box.y>=parent.y && box.x+box.width<=parent.x+parent.width+1 && box.y+box.height<=parent.y+parent.height+1,
								"each class name must fit beneath its portrait")
						}
					}
					if scenario == 9 {
						label := string(text.chars[:text.length])
						if label == menuui.shorten(classes[2].name,30) || label == menuui.shorten(classes[2].weapon,36) {
							parent := clay.GetElementData(clay.ID("SelectedClass")).boundingBox
							box := command.boundingBox
							testing.expect(t, box.x>=parent.x && box.y>=parent.y && box.x+box.width<=parent.x+parent.width+1 && box.y+box.height<=parent.y+parent.height+1,
								"long selected class and weapon names must fit their card")
						}
					}
				}
				if page == .HOME && view.online && view.ready && view.presentation == .COMPETITIVE {
					left := clay.GetElementData(clay.ID("Team",1)).boundingBox
					right := clay.GetElementData(clay.ID("Team",2)).boundingBox
					play := clay.GetElementData(clay.ID("Play")).boundingBox
					if scenario==0 { play_y=play.y }
					if scenario == 1 { testing.expect(t, abs(play.y-play_y)<1, "Play must stay fixed when selections are pending") }
					footer := clay.GetElementData(clay.ID("Footer")).boundingBox
					testing.expect(t, footer.y+footer.height <= ui.height && left.y+left.height < footer.y && right.y+right.height < footer.y, "rosters must leave the footer visible at every team size")
					for team in view.teams {
						if team.capacity > 4 { continue }
						count := 0
						for player in view.players { if player.team == team.id { count += 1 } }
						rows := max(count,team.capacity)
						box := clay.GetElementData(clay.ID("Roster", u32(team.id))).boundingBox
						testing.expectf(t, box.height >= f32(rows*88-4)*state.scale-1, "all competitive slots must fit without scrolling or clipping (size=%v scenario=%d team=%d height=%f)", size, scenario, team.id, box.height)
						for player, i in view.players {
							if player.team != team.id { continue }
							row := clay.GetElementData(clay.ID("RosterPlayer", u32(i))).boundingBox
							testing.expect(t, row.y >= box.y-1 && row.y+row.height <= box.y+box.height+1, "every player highlight must fit inside the roster")
							for command in commands.internalArray[:commands.length] {
								if command.commandType != .Text { continue }
								label := command.renderData.text.stringContents
								value := string(label.chars[:label.length])
								if value != menuui.shorten(player.name,22) && value != player.class_name && value != "You" { continue }
								bounds := command.boundingBox
								if bounds.x < row.x || bounds.x >= row.x+row.width || bounds.y < row.y || bounds.y >= row.y+row.height { continue }
								testing.expect(t, bounds.x >= row.x+10*state.scale-1 && bounds.x+bounds.width <= row.x+row.width-10*state.scale+1 &&
									bounds.y >= row.y+6*state.scale-1 && bounds.y+bounds.height <= row.y+row.height-6*state.scale+1,
									"roster names, classes, and You labels must fit with padding inside the highlight")
							}
						}
					}
					testing.expect(t, abs(left.width-right.width)<1 && abs(left.y-right.y)<1, "team panels must have equal widths and top alignment")
						testing.expect(t, play.x >= left.x+left.width && play.x+play.width <= right.x, "Play must sit between the rosters")
				}
				if view.presentation == .STANDARD && view.ready {
					for id in ([?]string{"StandardPlayPanel", "SelectedClass", "StandardPlayStatus"}) {
						box := clay.GetElementData(clay.ID(id)).boundingBox
						testing.expect(t, box.width>0 && box.height>0 && box.x>=0 && box.y>=0 && box.x+box.width<=ui.width+1 && box.y+box.height<=ui.height+1,
							"standard lobby controls must stay within the viewport")
					}
					if page == .HOME {
						play := clay.GetElementData(clay.ID("Play")).boundingBox
						if scenario==8 { play_y=play.y }
						testing.expect(t, abs(play.y-play_y)<1, "standard Play must stay fixed across team and pending states")
					}
				}
				if #config(MENU_PREVIEW, false) && (#config(MENU_PREVIEW_SCENARIO, -1) < 0 || scenario == #config(MENU_PREVIEW_SCENARIO, -1)) {
					pixels := make([]u8, int(size[0] * size[1] * 3))
					gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
					gl.ReadPixels(0, 0, size[0], size[1], gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
					header := fmt.aprintf("P6\n%d %d\n255\n", size[0], size[1])
					file := make([dynamic]u8)
					append(&file, ..transmute([]u8)header)
					for row := size[1] - 1; row >= 0; row -= 1 {
						offset := int(row * size[0] * 3)
						append(&file, ..pixels[offset:offset + int(size[0] * 3)])
					}
					path := fmt.aprintf("bin/menu_%d_%dx%d.ppm", scenario, size[0], size[1])
					testing.expect(t, os.write_entire_file(path, file[:]) == nil, "could not export menu preview")
					delete(path)
					delete(header)
					delete(file)
					delete(pixels)
				}
				if page == .LOADOUT {
					parent, return_focus := state.loadout_parent, state.loadout_return_focus
					state.previous = {}
					action := menuui.interact(&state, {escape=true}, view)
					testing.expect(t, state.page == parent && state.focus == return_focus && action.kind == .NONE,
						"Escape must return to class selection without resuming an active life")
					state.page = .LOADOUT
					menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
					state.previous, state.focus = {}, clay.ID("Back", u32(parent)).id
					menuui.interact(&state, {enter=true}, view)
					testing.expect(t, state.page == parent && state.focus == (parent == .HOME ? state.return_focus : return_focus), "Back must return to the parent class selection")
					state.page = .LOADOUT
					menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
					state.previous, state.focus = {}, clay.ID("LoadoutDone").id
					menuui.interact(&state, {enter=true}, view)
					testing.expect(t, state.page == .HOME && state.focus == state.return_focus, "Done must return directly to the lobby")
				}
			}
		}
	}
}
