package menu

import "core:fmt"
import clay "../third_party/clay"

selected :: proc(view: View) -> Class {
	for class in view.classes { if class.id == view.selected_class { return class } }
	return {}
}

// Keep the complete registry in View for equipped/selected class details. Only
// the competitive pickers hide classes excluded by the server's rules.
visible_classes :: proc(view: View) -> []Class {
	if view.presentation != .COMPETITIVE { return view.classes }
	classes := make([dynamic]Class, 0, len(view.classes), context.temp_allocator)
	for class in view.classes { if class.available { append(&classes, class) } }
	return classes[:]
}

class_selectable :: proc(view: View, class: Class) -> bool {
	return class.available && (class.limit == 0 || class.used < class.limit || view.confirmed_class == class.id)
}

play_label :: proc(view: View) -> string {
	if !view.active && view.respawn_remaining > 0 { return fmt.tprintf("Respawn in %d", int(view.respawn_remaining+0.999)) }
	return view.active ? "Resume" : view.has_life ? "Respawn" : "Enter Game"
}

play_reason :: proc(view: View) -> string {
	if !view.active && view.respawn_remaining > 0 { return "Waiting for respawn cooldown" }
	if view.active { return "" }
	if len(view.play_reason) > 0 { return view.play_reason }
	if !view.ready { return "Waiting for lobby data..." }
	if view.spawn_pending { return "Waiting for server spawn confirmation..." }
	if view.team_pending { return "Waiting for team confirmation..." }
	for class in view.classes {
		if class.id != view.selected_class { continue }
		if !class.available { return len(class.reason)>0 ? class.reason : "Choose an available class" }
		if class.limit>0 && class.used>=class.limit && view.confirmed_class!=class.id { return "Class limit reached. Choose another class." }
	}

	return ""
}

build :: proc(state: ^State, view: View, input: Input, width, height, delta: f32) -> clay.ClayArray(clay.RenderCommand) {
	clay.SetCurrentContext(state.ctx)
	prepare_settings(state, view)
	clay.SetLayoutDimensions({width, height})
	clay.SetPointerState(input.pointer, input.down)
	clay.UpdateScrollContainers(false, input.scroll, min(delta, 0.1))
	state.control_count = 0
	state.scale = max(0.4, min(width / 1600, height / 900))
	s := state.scale
	gap: f32 = view.presentation == .COMPETITIVE ? 16 : 24
	clay.BeginLayout()
	if clay.UI(clay.ID("MenuRoot"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32*s)), childGap = u16(gap*s)}}) {
		if clay.UI(clay.ID("Header"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48*s)}, childGap = u16(16*s), childAlignment = {y = .Center}}}) {
			text("KRODIN", 28, s)
			spacer()
			text(fmt.tprintf("%s / %s", view.map_name, view.mode), 20, s, MUTED)
			spacer()
			text(view.online && view.ready ? (view.ranked ? "Ranked" : view.presentation == .COMPETITIVE ? "Competitive" : "Connected") : view.local_practice ? "Local practice" : view.auth_pending && !view.connecting ? "Logging in" : view.online || view.connecting ? "Connecting" : "Join a lobby", 16, s)
		}
		if clay.UI(clay.ID("Page"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(gap*s), childAlignment = {x = .Center}}}) {
			if view.online && view.ready || view.local_practice {
				if view.presentation == .COMPETITIVE { lobby(state, view, width-64*s) }
				else { standard_lobby(state, view) }
			}
			else {
				spacer()
				if clay.UI(clay.ID("ConnectionScreen"))({layout = {sizing = {width = clay.SizingFixed(760*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32*s)), childGap = u16(24*s)}, backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(4*s)}) {
					text(view.auth_pending && !view.connecting ? "Logging in" : view.online || view.connecting ? "Connecting to lobby" : "Join a lobby", 32, s)
					if state.page == .HOME { session(state, view) }
					button(state, "Local practice", "Practice", {kind = .LOCAL_PRACTICE})
				}
				spacer()
			}
		}
		if clay.UI(clay.ID("Footer"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48*s)}, childGap = u16(16*s), childAlignment = {y = .Center}}}) {
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(200*s)}}}) { button(state, "Session / Invite", "Session", {index = i32(Page.SESSION)}) }
			spacer()
			text("Tab  Navigate     Enter  Select     Esc  Back", 16, s, MUTED)
			spacer()
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(144*s)}}}) { button(state, "Settings", "Settings", {index = i32(Page.SETTINGS)}) }
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(112*s)}}}) { button(state, "Quit", "Quit", {kind = .QUIT}) }
		}
		if state.page != .HOME {
			// Modal controls replace the lobby's interaction list (mouse and Tab).
			state.control_count = 0
			if clay.UI(clay.ID("ModalScrim"))({layout = {sizing = {width = clay.SizingFixed(width), height = clay.SizingFixed(height)}, childAlignment = {x = .Center, y = .Center}}, backgroundColor = {0,0,0,160}, floating = {attachTo = .Root, zIndex = 10}}) {
				if state.page == .SETTINGS || state.page == .CONTROLS {
					settings_window(state, view)
				} else if clay.UI(clay.ID("Overlay"))({layout = {sizing = {width = clay.SizingFixed((state.page == .LOADOUT ? 1040 : 880)*s), height = clay.SizingFixed(752*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32*s)), childGap = u16(16*s)}, backgroundColor = {20,23,28,255}, cornerRadius = clay.CornerRadiusAll(4*s), border = {color = {75,80,88,255}, width = clay.BorderOutside(1)}}) {
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(52*s)}}}) {
						if clay.UI()({layout = {sizing = {width = clay.SizingFixed(136*s)}}}) { button(state, "Back", "Back", {index = i32(back_page(state))}) }
						if state.page == .LOADOUT {
							spacer()
							if clay.UI()({layout = {sizing = {width = clay.SizingFixed(136*s)}}}) { button(state, "Done", "LoadoutDone", {index = i32(Page.HOME)}, primary = true) }
						}
					}
					switch state.page {
					case .HOME:
					case .SETTINGS, .CONTROLS:
					case .CLASSES: class_picker(state, view)
					case .LOADOUT: class_loadout(state, view)
					case .SESSION:
						text("Session / Invite", 32, s)
						text(view.lobby_name, 20, s, MUTED)
						session(state, view)
					}
				}
			}
		}
	}
	commands := clay.EndLayout(max(0, delta))
	if state.settings_dropdown != .NONE {
		for control in state.controls[:state.control_count] {
			if control.id.id == state.focus { focus_visible(control, state.page); break }
		}
	}
	return commands
}

lobby :: proc(state: ^State, view: View, available_width: f32) {
	s := state.scale
	classes := visible_classes(view)
	// A lobby allowing every class still needs room for four padded roster rows.
	tile_size := clamp((available_width/s+8)/f32(max(1,len(classes)))-8, 88, 112)
	columns := max(1, int((available_width/s+8)/(tile_size+8)))
	rows := max(1, (len(classes)+columns-1)/columns)
	if clay.UI(clay.ID("ClassStrip"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed((f32(rows)*tile_size+f32(rows-1)*8)*s)}, layoutDirection = .TopToBottom, childGap = u16(8*s)}}) {
		for start := 0; start < len(classes); start += columns {
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(tile_size*s)}, childGap = u16(8*s), childAlignment = {x = .Center}}}) {
				for class in classes[start:min(start+columns, len(classes))] { class_tile(state, view, class, "Class", compact = true, compact_size = tile_size) }
			}
		}
		if len(classes) == 0 { text("No classes are allowed in this lobby", 20, s, MUTED) }
	}
	detail := selected(view)
	for class in classes {
		if clay.PointerOver(clay.ID("Class", u32(class.id))) || state.focus == clay.ID("Class", u32(class.id)).id { detail = class }
	}
	if clay.UI(clay.ID("ClassHint"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(32*s)}, childGap = u16(16*s), childAlignment = {y = .Center}}}) {
		text(detail.name, 20, s)
		text(detail.weapon, 16, s, MUTED)
		if !detail.available { text(len(detail.reason) > 0 ? detail.reason : "Unavailable in this lobby", 16, s, MUTED) }
		if detail.limit > 0 { text(fmt.tprintf("%d / %d in use", detail.used, detail.limit), 16, s, MUTED) }
		spacer()
		text(fmt.tprintf("Secondary: %s", view.secondary_name), 16, s, MUTED)
	}
	if clay.UI(clay.ID("Lobby"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, childGap = u16(32*s), childAlignment = {x = .Center, y = .Center}}}) {
		roster(state, view, view.teams[0])
		if clay.UI(clay.ID("PlayPanel"))({layout = {sizing = {width = clay.SizingFixed(336*s), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(16*s), childAlignment = {x = .Center}}}) {
			text("VS", 24, s, MUTED)
			text(fmt.tprintf("%d : %d", view.teams[0].score, view.teams[1].score), 32, s)
			spacer()
			if clay.UI(clay.ID("PlayAction"))({layout = {sizing = {width = clay.SizingFixed(336*s), height = clay.SizingFixed(208*s)}, layoutDirection = .TopToBottom, childGap = u16(16*s), childAlignment = {x = .Center}}, floating = {attachTo = .ElementWithId, parentId = clay.ID("PlayPanel").id, zIndex = 1, attachment = {element = .CenterCenter, parent = .CenterCenter}, offset = {0,40*s}}}) {
			label := play_label(view)
			reason := play_reason(view)
			button(state, label, "Play", {kind = .PLAY}, primary = true, enabled = len(reason) == 0)
			class := selected(view)
			text(fmt.tprintf("%s / %s", class.name, class.weapon), 18, s)
			if view.active && !view.live_class_changes && view.confirmed_class != view.selected_class { text("Selected for next spawn", 16, s, MUTED) }
			else if view.secondary_pending { text(view.live_class_changes ? "Secondary awaiting server confirmation" : "Secondary selected for next spawn", 16, s, MUTED) }
			if len(view.secondary_reason) > 0 { text(view.secondary_reason, 16, s, MUTED) }
			if view.class_pending { text("Class awaiting server confirmation", 16, s, MUTED) }
			if len(reason) > 0 { text(reason, 16, s, MUTED) }
			}
			spacer()
			text(view.match_status, 16, s, MUTED)
			text(view.selection_status, 16, s)
		}
		roster(state, view, view.teams[1])
	}
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(28*s)}, childGap = u16(16*s)}}) {
		text(view.lobby_name, 16, s)
		spacer()
		text(view.join_status, 16, s, MUTED)
	}
}

class_tile :: proc(state: ^State, view: View, class: Class, prefix: string, compact: bool = false, compact_size: f32 = 112) {
	s := state.scale
	size: f32 = compact ? compact_size : 144
	portrait_size: f32 = compact ? compact_size-48 : 88
	name_height: f32 = compact ? 28 : 32
	id := clay.ID(prefix, u32(class.id))
	// Restricted tiles stay focusable so keyboard users can read why.
	available := class_selectable(view, class)
	register(state, {id = id, enabled = true, action = {kind = available ? .SELECT_CLASS : .INSPECT_CLASS, index = class.id}})
	chosen := class.id == view.selected_class
	if clay.UI(id)({layout = {sizing = {width = clay.SizingFixed(size*s), height = clay.SizingFixed(size*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(8*s)), childGap = u16(4*s), childAlignment = {x = .Center}}, backgroundColor = chosen ? SELECTED : PANEL, border = {color = chosen || state.focus == id.id ? WHITE : clay.Color{60,64,72,180}, width = clay.BorderOutside(chosen || state.focus == id.id ? 2 : 1)}, cornerRadius = clay.CornerRadiusAll(4*s)}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(portrait_size*s), height = clay.SizingFixed(portrait_size*s)}, childAlignment = {x = .Center, y = .Center}}, image = {imageData = class.portrait}}) {
			if class.portrait == nil { text(fmt.tprintf("%02d", class.id + 1), 32, s, class.available ? WHITE : MUTED) }
		}
		if clay.UI(clay.ID(fmt.tprintf("%sName", prefix), u32(class.id)))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(name_height*s)}, childAlignment = {x = .Center, y = .Center}}}) {
			text(class.name, compact && compact_size < 100 ? 14 : 16, s, available ? WHITE : MUTED)
		}
	}
}

class_picker :: proc(state: ^State, view: View) {
	s := state.scale
	classes := visible_classes(view)
	compact := view.presentation == .COMPETITIVE
	columns := compact ? 6 : 5
	tile_size: f32 = compact ? 112 : 144
	text("Choose class", 32, s)
	if clay.UI(clay.ID("ClassPicker"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(16*s), childAlignment = {x = .Center}}, clip = {vertical = true, childOffset = clay.GetScrollOffset()}}) {
		for start := 0; start < len(classes); start += columns {
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(tile_size*s)}, childGap = u16(16*s), childAlignment = {x = .Center}}}) {
				for class in classes[start:min(start+columns, len(classes))] { class_tile(state, view, class, "ClassChoice", compact) }
			}
		}
	}
	detail := selected(view)
	for class in classes {
		if clay.PointerOver(clay.ID("ClassChoice", u32(class.id))) || state.focus == clay.ID("ClassChoice", u32(class.id)).id { detail = class }
	}
	if clay.UI(clay.ID("PickerHint"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(80*s)}, layoutDirection = .TopToBottom, childGap = u16(4*s)}}) {
		text(fmt.tprintf("%s / %s", detail.name, detail.weapon), 20, s)
		if !detail.available { text(len(detail.reason)>0 ? detail.reason : "Unavailable in this lobby", 16, s, MUTED) }
		if detail.limit > 0 { text(fmt.tprintf("%d / %d in use", detail.used, detail.limit), 16, s, MUTED) }
		text(view.selection_status, 16, s, MUTED)
	}
}

class_loadout :: proc(state: ^State, view: View) {
	s := state.scale
	class := selected(view)
	if clay.UI(clay.ID("ClassLoadout"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, childGap = u16(32*s)}}) {
		if clay.UI(clay.ID("LoadoutClass"))({layout = {sizing = {width = clay.SizingFixed(240*s), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(16*s)}}) {
			text("Class loadout", 18, s, MUTED)
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(192*s), height = clay.SizingFixed(192*s)}}, image = {imageData = class.portrait}}) {}
			text(shorten(class.name, 32), 28, s)
			if class.health > 0 { stat("Health", fmt.tprintf("%d", class.health), s) }
			if class.wall_jump { text("Wall jump", 16, s, MUTED) }
		}
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(16*s)}}) {
			text("Primary", 22, s)
			if clay.UI(clay.ID("LoadoutPrimary"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(96*s)}, padding = clay.PaddingAll(u16(16*s)), childGap = u16(24*s), childAlignment = {y = .Center}}, backgroundColor = PANEL}) {
				if clay.UI()({layout = {sizing = {width = clay.SizingFixed(128*s), height = clay.SizingFixed(64*s)}}, image = {imageData = class.weapon_icon}}) {}
				text(shorten(class.weapon, 36), 22, s)
			}
			text("Secondary", 22, s)
			if len(view.secondary_reason) > 0 {
				if clay.UI(clay.ID("LoadoutRestriction"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, padding = clay.PaddingAll(u16(24*s)), layoutDirection = .TopToBottom}, backgroundColor = PANEL}) {
					text(view.secondary_reason, 20, s, MUTED)
				}
			} else if clay.UI(clay.ID("SecondaryPicker"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(12*s)}, clip = {vertical = true, childOffset = clay.GetScrollOffset()}}) {
				for start := 0; start < len(view.secondaries); start += 2 {
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(88*s)}, childGap = u16(12*s)}}) {
						for weapon in view.secondaries[start:min(start+2, len(view.secondaries))] { secondary_choice(state, view, weapon) }
						if start+1 == len(view.secondaries) { spacer() }
					}
				}
			}
			if clay.UI(clay.ID("LoadoutStatus"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(88*s)}, layoutDirection = .TopToBottom, childGap = u16(8*s)}}) {
				if len(view.secondary_reason) == 0 { text(fmt.tprintf("Selected: %s", view.secondary_name), 18, s, MUTED) }
				if view.active && view.live_class_changes { text(view.class_pending || view.secondary_pending ? "Loadout awaiting server confirmation" : "Changes apply immediately during this break", 16, s, MUTED) }
				else if view.active { text("Changes apply on your next spawn", 16, s, MUTED) }
				else if view.class_pending { text("Class awaiting server confirmation", 16, s, MUTED) }
				text(view.selection_status, 16, s)
			}
		}
	}
}

secondary_choice :: proc(state: ^State, view: View, weapon: Secondary) {
	s := state.scale
	id := clay.ID("SecondaryChoice", u32(weapon.id))
	chosen := weapon.id == view.selected_secondary
	register(state, {id = id, enabled = true, action = {kind = .SELECT_SECONDARY, index = weapon.id}})
	if clay.UI(id)({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(88*s)}, padding = clay.PaddingAll(u16(12*s)), childGap = u16(12*s), childAlignment = {y = .Center}}, backgroundColor = chosen ? SELECTED : PANEL, border = {color = chosen || state.focus == id.id ? WHITE : clay.Color{60,64,72,180}, width = clay.BorderOutside(chosen || state.focus == id.id ? 2 : 1)}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(80*s), height = clay.SizingFixed(48*s)}}, image = {imageData = weapon.icon}}) {}
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(4*s)}}) {
			text(weapon.name, 18, s)
			if chosen { text("Selected", 14, s, MUTED) }
		}
	}
}

standard_lobby :: proc(state: ^State, view: View) {
	s := state.scale
	if clay.UI(clay.ID("StandardLobby"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, childAlignment = {x = .Center, y = .Center}}}) {
		if clay.UI(clay.ID("StandardPlayPanel"))({layout = {sizing = {width = clay.SizingFixed(560*s), height = clay.SizingFixed(536*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(24*s)), childGap = u16(16*s)}, backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(4*s)}) {
			if view.team_selection {
				if clay.UI(clay.ID("TeamPicker"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(84*s)}, layoutDirection = .TopToBottom, childGap = u16(8*s)}}) {
					text(view.confirmed_team > 0 && view.confirmed_team <= 2 ? fmt.tprintf("Team: %s", shorten(view.teams[view.confirmed_team-1].name, 30)) : "Choose team", 18, s, MUTED)
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(52*s)}, childGap = u16(16*s)}}) {
						for team in view.teams { team_button(state, view, team, 14) }
					}
				}
			} else {
				if clay.UI()({layout = {sizing = {height = clay.SizingFixed(84*s)}, childAlignment = {y = .Center}}}) {
					text(view.confirmed_team > 0 && view.confirmed_team <= 2 ? fmt.tprintf("Team: %s", shorten(view.teams[view.confirmed_team-1].name, 30)) : "Ready to play", 18, s, MUTED)
				}
			}
			button(state, play_label(view), "Play", {kind = .PLAY}, primary = true, enabled = len(play_reason(view)) == 0)
			if clay.UI(clay.ID("StandardPlayStatus"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(76*s)}, layoutDirection = .TopToBottom, childGap = u16(4*s)}}) {
				text(play_reason(view), 16, s, MUTED)
				text(view.selection_status, 16, s)
			}
			class := selected(view)
			if clay.UI(clay.ID("SelectedClass"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(88*s)}, childGap = u16(16*s), childAlignment = {y = .Center}}}) {
				if clay.UI()({layout = {sizing = {width = clay.SizingFixed(88*s), height = clay.SizingFixed(88*s)}}, image = {imageData = class.portrait}}) {
					if class.portrait == nil { text(fmt.tprintf("%02d", class.id+1), 32, s) }
				}
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(4*s)}}) {
					text(shorten(class.name, 30), 22, s)
					text(shorten(class.weapon, 36), 16, s, MUTED)
					text(fmt.tprintf("Secondary: %s", view.secondary_name), 16, s, MUTED)
				}
			}
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(52*s)}, childGap = u16(16*s)}}) {
				button(state, "Change class", "ChangeClass", {index = i32(Page.CLASSES)})
			}
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48*s)}, layoutDirection = .TopToBottom, childGap = u16(4*s)}}) {
				if len(view.secondary_reason) > 0 { text(view.secondary_reason, 16, s, MUTED) }
				else if view.active && (view.confirmed_class != view.selected_class || view.secondary_pending) { text(view.live_class_changes ? "Loadout awaiting server confirmation" : "Selected for next spawn", 16, s, MUTED) }
				else if view.class_pending { text("Class awaiting server confirmation", 16, s, MUTED) }
				else { text(view.match_status, 16, s, MUTED) }
			}
		}
	}
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(40*s)}, childGap = u16(16*s)}}) {
		text(view.lobby_name, 16, s)
		spacer()
		text(view.join_status, 16, s, MUTED)
	}
}

team_button :: proc(state: ^State, view: View, team: Team, name_limit: int = 20) {
	count := 0
	for player in view.players { if player.team == team.id { count += 1 } }
	mine := view.confirmed_team == team.id
	pending := view.team_pending && (view.requested_team == team.id || view.requested_team == 0 && mine)
	label := pending ? (view.requested_team == 0 ? "Leaving..." : "Joining...") : mine ? "Leave team" : team.capacity > 0 && count >= team.capacity ? fmt.tprintf("%s full", shorten(team.name, name_limit)) : fmt.tprintf("Join %s", shorten(team.name, name_limit))
	button(state, label, "JoinTeam", {kind = .SELECT_TEAM, index = mine ? 0 : team.id}, selected = mine, enabled = team.available && !view.team_pending && (mine || team.capacity <= 0 || count < team.capacity))
}

roster :: proc(state: ^State, view: View, team: Team) {
	s := state.scale
	accent := team.id == 1 ? clay.Color{240,101,108,255} : clay.Color{104,167,245,255}
	count := 0
	for player in view.players { if player.team == team.id { count += 1 } }
	panel_height := f32(144 + clamp(max(count, team.capacity), 1, 4)*88)*s
	if clay.UI(clay.ID("Team", u32(team.id)))({layout = {sizing = {width = clay.SizingGrow({0,440*s}), height = clay.SizingGrow({0,panel_height})}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(12*s)), childGap = u16(8*s)}, backgroundColor = PANEL, border = {color = accent, width = {top = 2}}, cornerRadius = clay.CornerRadiusAll(4*s)}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(8*s), childAlignment = {y = .Center}}}) {
			text(shorten(team.name,24), 32, s, accent)
			spacer()
			text(team.capacity > 0 ? fmt.tprintf("%d / %d", count, team.capacity) : fmt.tprintf("%d players", count), 20, s, MUTED)
		}
		if clay.UI(clay.ID("Roster", u32(team.id)))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow({0,f32(clamp(max(count, team.capacity),1,4)*88-4)*s})}, layoutDirection = .TopToBottom, childGap = u16(4*s)}, clip = {vertical = true, childOffset = clay.GetScrollOffset()}}) {
			for player, i in view.players {
				if player.team != team.id { continue }
				if clay.UI(clay.ID("RosterPlayer", u32(i)))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(84*s)}, padding = {left = u16(12*s), right = u16(12*s), top = u16(8*s), bottom = u16(8*s)}, childGap = u16(8*s), childAlignment = {y = .Center}}, backgroundColor = player.is_you ? SELECTED : clay.Color{}}) {
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
						text(shorten(player.name, 22), 26, s)
						text(player.class_name, 20, s, MUTED)
					}
					if player.is_you { text("You", 20, s, accent) }
				}
			}
			for _ in 0 ..< clamp(team.capacity-count,0,32) {
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(84*s)}, padding = {left = u16(12*s), right = u16(12*s)}, childAlignment = {y = .Center}}}) { text("Open slot", 24, s, MUTED) }
			}
		}
		team_button(state, view, team)
		if len(team.reason) > 0 { text(team.reason, 16, s, MUTED) }
	}
}

shorten :: proc(value: string, limit: int) -> string {
	if len(value) <= limit { return value }
	return fmt.tprintf("%s...", value[:limit-3])
}

session :: proc(state: ^State, view: View) {
	s := state.scale
	if view.browser_access_supported {
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(16*s)}}) {
			button(state, view.auth_pending ? "Logging in..." : "Login", "Login", {kind = .LOGIN}, enabled = !view.auth_pending && !view.connecting)
			button(state, "Forget browser session", "ForgetBrowserSession", {kind = .FORGET_BROWSER_SESSION})
		}
	}
	text("Invite link", 18, s, MUTED)
	id := clay.ID("Invite")
	register(state, {id = id, enabled = true, action = {kind = .EDIT_INVITE}})
	if clay.UI(id)({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(56*s)}, padding = clay.PaddingAll(u16(12*s)), childAlignment = {y = .Center}}, backgroundColor = SURFACE, cornerRadius = clay.CornerRadiusAll(4*s), border = {color = WHITE, width = clay.BorderOutside(state.focus == id.id ? 1 : 0)}}) {
		value := invite(state)
		// Keep the insertion end visible while entering long links.
		if len(value) > 65 { value = value[len(value)-65:] }
		// Clip the text inside the field so the focus border stays intact.
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, childAlignment = {y = .Center}}, clip = {horizontal = true}}) {
			text(len(value) == 0 ? "Paste or type a lobby invite" : value, 20, s, len(value) == 0 ? MUTED : WHITE)
		}
	}
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(16*s)}}) {
		button(state, "Paste", "Paste", {kind = .PASTE})
		button(state, view.auth_pending && view.connecting ? "Preparing access..." : view.connecting ? "Connecting..." : "Join", "JoinLink", {kind = .JOIN_LINK}, primary = true, enabled = len(invite(state)) > 0 && !view.connecting && !view.auth_pending)
	}
	if view.connecting || view.auth_pending { button(state, "Cancel", "CancelJoin", {kind = .CANCEL_JOIN}) }
	text(len(view.join_status) > 0 ? view.join_status : "Enter an invite to connect to a lobby.", 18, s, MUTED)
	if view.online || view.local_practice {
		rule(s)
		text(shorten(view.current_invite, 80), 16, s, MUTED)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(16*s)}}) {
			button(state, "Copy current invite", "CopyInvite", {kind = .COPY_INVITE}, enabled = len(view.current_invite) > 0)
			button(state, "Leave session", "LeaveSession", {kind = .LEAVE_SESSION})
		}
	}
}
