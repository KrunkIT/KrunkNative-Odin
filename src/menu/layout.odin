package menu

import "core:fmt"
import clay "../third_party/clay"

selected :: proc(view: View) -> Class {
	for class in view.classes { if class.id == view.selected_class { return class } }
	return {}
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
	clay.SetLayoutDimensions({width, height})
	clay.SetPointerState(input.pointer, input.down)
	clay.UpdateScrollContainers(false, input.scroll, min(delta, 0.1))
	state.control_count = 0
	state.scale = max(0.4, min(width / 1600, height / 900))
	s := state.scale
	clay.BeginLayout()
	if clay.UI(clay.ID("MenuRoot"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32*s)), childGap = u16(24*s)}}) {
		if clay.UI(clay.ID("Header"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48*s)}, childGap = u16(16*s), childAlignment = {y = .Center}}}) {
			text("KRUNK NATIVE", 28, s)
			spacer()
			text(fmt.tprintf("%s / %s", view.map_name, view.mode), 20, s, MUTED)
			spacer()
			text(view.online && view.ready ? (view.ranked ? "Ranked" : view.presentation == .COMPETITIVE ? "Competitive" : "Connected") : view.local_practice ? "Local practice" : view.online || view.connecting ? "Connecting" : "Join a lobby", 16, s)
		}
		if clay.UI(clay.ID("Page"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(24*s), childAlignment = {x = .Center}}}) {
			if view.online && view.ready || view.local_practice {
				if view.presentation == .COMPETITIVE { lobby(state, view) }
				else { standard_lobby(state, view) }
			}
			else {
				spacer()
				if clay.UI(clay.ID("ConnectionScreen"))({layout = {sizing = {width = clay.SizingFixed(760*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32*s)), childGap = u16(24*s)}, backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(4*s)}) {
					text(view.online || view.connecting ? "Connecting to lobby" : "Join a lobby", 32, s)
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
				if clay.UI(clay.ID("Overlay"))({layout = {sizing = {width = clay.SizingFixed((state.page == .LOADOUT ? 1040 : 880)*s), height = clay.SizingFixed(752*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32*s)), childGap = u16(16*s)}, backgroundColor = {20,23,28,255}, cornerRadius = clay.CornerRadiusAll(4*s), border = {color = {75,80,88,255}, width = clay.BorderOutside(1)}}) {
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(52*s)}}}) {
						if clay.UI()({layout = {sizing = {width = clay.SizingFixed(136*s)}}}) { button(state, "Back", "Back", {index = i32(back_page(state))}) }
						if state.page == .LOADOUT {
							spacer()
							if clay.UI()({layout = {sizing = {width = clay.SizingFixed(136*s)}}}) { button(state, "Done", "LoadoutDone", {index = i32(Page.HOME)}, primary = true) }
						}
					}
					switch state.page {
					case .HOME:
					case .SETTINGS: settings(state, view)
					case .CONTROLS: controls(state)
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
	return clay.EndLayout(max(0, delta))
}

lobby :: proc(state: ^State, view: View) {
	s := state.scale
	if clay.UI(clay.ID("ClassStrip"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(144*s)}, childGap = u16(8*s)}, clip = {horizontal = true, childOffset = clay.GetScrollOffset()}}) {
		for class in view.classes {
			class_tile(state, view, class, "Class")
		}
	}
	detail := selected(view)
	for class in view.classes {
		if clay.PointerOver(clay.ID("Class", u32(class.id))) || state.focus == clay.ID("Class", u32(class.id)).id { detail = class }
	}
	if clay.UI(clay.ID("ClassHint"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(52*s)}, childGap = u16(16*s), childAlignment = {y = .Center}}}) {
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
			if view.active && view.confirmed_class != view.selected_class { text("Selected for next spawn", 16, s, MUTED) }
			else if view.secondary_pending { text("Secondary selected for next spawn", 16, s, MUTED) }
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
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(40*s)}, childGap = u16(16*s)}}) {
		text(view.lobby_name, 16, s)
		spacer()
		text(view.join_status, 16, s, MUTED)
	}
}

class_tile :: proc(state: ^State, view: View, class: Class, prefix: string) {
	s := state.scale
	id := clay.ID(prefix, u32(class.id))
	// Restricted tiles stay focusable so keyboard users can read why.
	available := class_selectable(view, class)
	register(state, {id = id, enabled = true, action = {kind = available ? .SELECT_CLASS : .INSPECT_CLASS, index = class.id}})
	chosen := class.id == view.selected_class
	if clay.UI(id)({layout = {sizing = {width = clay.SizingFixed(144*s), height = clay.SizingFixed(144*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(8*s)), childGap = u16(4*s), childAlignment = {x = .Center}}, backgroundColor = chosen ? SELECTED : PANEL, border = {color = chosen || state.focus == id.id ? WHITE : clay.Color{60,64,72,180}, width = clay.BorderOutside(chosen || state.focus == id.id ? 2 : 1)}, cornerRadius = clay.CornerRadiusAll(4*s)}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(88*s), height = clay.SizingFixed(88*s)}, childAlignment = {x = .Center, y = .Center}}, image = {imageData = class.portrait}}) {
			if class.portrait == nil { text(fmt.tprintf("%02d", class.id + 1), 32, s, class.available ? WHITE : MUTED) }
		}
		if clay.UI(clay.ID(fmt.tprintf("%sName", prefix), u32(class.id)))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(32*s)}, childAlignment = {x = .Center, y = .Center}}}) {
			text(class.name, 16, s, available ? WHITE : MUTED)
		}
	}
}

class_picker :: proc(state: ^State, view: View) {
	s := state.scale
	text("Choose class", 32, s)
	if clay.UI(clay.ID("ClassPicker"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(16*s), childAlignment = {x = .Center}}, clip = {vertical = true, childOffset = clay.GetScrollOffset()}}) {
		for start := 0; start < len(view.classes); start += 5 {
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(144*s)}, childGap = u16(16*s), childAlignment = {x = .Center}}}) {
				for class in view.classes[start:min(start+5, len(view.classes))] { class_tile(state, view, class, "ClassChoice") }
			}
		}
	}
	detail := selected(view)
	for class in view.classes {
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
				if view.active { text("Changes apply on your next spawn", 16, s, MUTED) }
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
				else if view.active && (view.confirmed_class != view.selected_class || view.secondary_pending) { text("Selected for next spawn", 16, s, MUTED) }
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
	panel_height := f32(200 + clamp(max(count, team.capacity), 1, 4)*60)*s
	if clay.UI(clay.ID("Team", u32(team.id)))({layout = {sizing = {width = clay.SizingGrow({0,440*s}), height = clay.SizingGrow({0,panel_height})}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(16*s)), childGap = u16(12*s)}, backgroundColor = PANEL, border = {color = accent, width = {top = 2}}, cornerRadius = clay.CornerRadiusAll(4*s)}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(8*s), childAlignment = {y = .Center}}}) {
			text(shorten(team.name,24), 32, s, accent)
			spacer()
			text(team.capacity > 0 ? fmt.tprintf("%d / %d", count, team.capacity) : fmt.tprintf("%d players", count), 20, s, MUTED)
		}
		if clay.UI(clay.ID("Roster", u32(team.id)))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow({0,f32(clamp(max(count, team.capacity),1,4)*60-4)*s})}, layoutDirection = .TopToBottom, childGap = u16(4*s)}, clip = {vertical = true, childOffset = clay.GetScrollOffset()}}) {
			for player in view.players {
				if player.team != team.id { continue }
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(56*s)}, childGap = u16(8*s), childAlignment = {y = .Center}}, backgroundColor = player.is_you ? SELECTED : clay.Color{}}) {
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
						text(shorten(player.name, 22), 26, s)
						text(player.class_name, 20, s, MUTED)
					}
					if player.is_you { text("You", 20, s, accent) }
				}
			}
			for _ in 0 ..< clamp(team.capacity-count,0,32) {
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(56*s)}, childAlignment = {y = .Center}}}) { text("Open slot", 24, s, MUTED) }
			}
		}
		mine := view.confirmed_team == team.id
		pending := view.team_pending && (view.requested_team == team.id || mine)
		label := pending ? "Joining..." : mine ? "Leave Team" : fmt.tprintf("Join %s", shorten(team.name,20))
		button(state, label, "JoinTeam", {kind = .SELECT_TEAM, index = mine ? 0 : team.id}, selected = mine, enabled = team.available && !view.team_pending && (mine || team.capacity <= 0 || count < team.capacity))
		if len(team.reason) > 0 { text(team.reason, 16, s, MUTED) }
		else if !mine && team.capacity > 0 && count >= team.capacity { text("Team is full", 16, s, MUTED) }
	}
}

shorten :: proc(value: string, limit: int) -> string {
	if len(value) <= limit { return value }
	return fmt.tprintf("%s...", value[:limit-3])
}

session :: proc(state: ^State, view: View) {
	s := state.scale
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
		button(state, view.connecting ? "Connecting..." : "Join", "JoinLink", {kind = .JOIN_LINK}, primary = true, enabled = len(invite(state)) > 0 && !view.connecting)
	}
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

settings :: proc(state: ^State, view: View) {
	s := state.scale
	text("Settings", 32, s)
	text("Video / Input / HUD", 16, s, MUTED)
	button(state, "Controls", "Controls", {index = i32(Page.CONTROLS)})
	if clay.UI(clay.ID("SettingsPanel"))({
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(26 * s)), childGap = u16(18 * s)},
		backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(8 * s), clip = {vertical = true, childOffset = clay.GetScrollOffset()},
	}) {
		text("Display mode", 13, s, MUTED)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(12 * s)}}) {
			labels := [3]string{"Windowed", "Borderless", "Fullscreen"}
			for label, i in labels {
				button(state, label, "DisplayMode", {kind = .DISPLAY_MODE, index = i32(i)}, view.display_mode == i32(i))
			}
		}
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(12 * s), childAlignment = {y = .Center}}}) {
			text("Resolution", 15, s)
			spacer()
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(55 * s)}}}) { button(state, "<", "ResolutionMinus", {kind = .RESOLUTION, index = -1}) }
			text(view.resolution, 17, s, ACCENT)
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(55 * s)}}}) { button(state, ">", "ResolutionPlus", {kind = .RESOLUTION, index = 1}) }
		}
		rule(s)
		stat("Mouse sensitivity", fmt.tprintf("%d%%", i32(view.sensitivity * 100 + 0.5)), s)
		id := clay.ID("Sensitivity")
		register(state, {id = id, enabled = true, slider = true})
		if clay.UI(id)({
			layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(38 * s)}, childAlignment = {y = .Center}},
			border = {color = ACCENT, width = clay.BorderOutside(state.focus == id.id ? 1 : 0)},
		}) {
			progress := clamp((view.sensitivity - 0.1) / 1.9, 0.001, 0.999)
			if clay.UI()({layout = {sizing = {width = clay.SizingPercent(progress), height = clay.SizingFixed(8 * s)}}, backgroundColor = ACCENT}) {}
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(8 * s)}}, backgroundColor = SURFACE}) {}
		}
		text("Drag to adjust. Use Left / Right when focused.", 12, s, MUTED)
		rule(s)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childAlignment = {y = .Center}}}) {
			text("Show FPS", 15, s)
			spacer()
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(140 * s)}}}) { button(state, view.show_fps ? "ON" : "OFF", "Fps", {kind = .FPS}, view.show_fps) }
		}
	}
}

controls :: proc(state: ^State) {
	s := state.scale
	text("LEARN THE CONTROLS", 32, s)
	text("Keyboard and mouse", 16, s, MUTED)
	if clay.UI(clay.ID("ControlsPanel"))({
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(26 * s)), childGap = u16(15 * s)},
		backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(8 * s), clip = {vertical = true, childOffset = clay.GetScrollOffset()},
	}) {
		rows := [9][2]string{{"MOVE", "W / A / S / D"}, {"JUMP", "SPACE"}, {"CROUCH / SLIDE", "LEFT SHIFT"}, {"FIRE / AIM", "LEFT / RIGHT MOUSE"}, {"RELOAD", "R"}, {"SECONDARY / MELEE", "E / Q"}, {"MENU / RESUME", "ESC"}, {"FULLSCREEN", "F11"}, {"WALL JUMP", "RELEASE + PRESS SPACE AT A WALL"}}
		for row in rows {
			stat(row[0], row[1], s)
			rule(s)
		}
		text("Wall jumping is available to Run N Gun, Agent, and Runner. Hold crouch against a wall while falling to slow your descent.", 14, s, MUTED)
	}
}
