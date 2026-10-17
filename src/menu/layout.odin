package menu

import "core:fmt"
import clay "../third_party/clay"

selected :: proc(view: View) -> Class {
	for class in view.classes { if class.id == view.selected_class { return class } }
	return {}
}

build :: proc(state: ^State, view: View, input: Input, width, height, delta: f32) -> clay.ClayArray(clay.RenderCommand) {
	clay.SetCurrentContext(state.ctx)
	clay.SetLayoutDimensions({width, height})
	clay.SetPointerState(input.pointer, input.down)
	clay.UpdateScrollContainers(false, input.scroll, min(delta, 0.1))
	state.control_count = 0
	state.scale = clamp(min(width / 1440, height / 900), 0.5, 1.5)
	s := state.scale
	clay.BeginLayout()
	if clay.UI(clay.ID("MenuRoot"))({
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32 * s)), childGap = u16(22 * s)},
	}) {
		if clay.UI(clay.ID("Header"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(64 * s)}, childGap = u16(12 * s), childAlignment = {y = .Center}}}) {
			text("KRUNK", 34, s, ACCENT)
			text("NATIVE", 34, s)
			spacer()
			text(view.online ? "CONNECTED" : "OFFLINE SESSION", 13, s, ACCENT)
		}
		if clay.UI(clay.ID("MenuBody"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, childGap = u16(24 * s)}}) {
			if clay.UI(clay.ID("Sidebar"))({
				layout = {sizing = {width = clay.SizingFixed(220 * s), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(18 * s)), childGap = u16(10 * s)},
				backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(8 * s),
			}) {
				text("YOUR SESSION", 12, s, MUTED)
				button(state, "PLAY", "NavHome", {index = i32(Page.HOME)}, state.page == .HOME)
				button(state, "CLASSES", "NavClasses", {index = i32(Page.CLASSES)}, state.page == .CLASSES)
				button(state, "SETTINGS", "NavSettings", {index = i32(Page.SETTINGS)}, state.page == .SETTINGS)
				button(state, "CONTROLS", "NavControls", {index = i32(Page.CONTROLS)}, state.page == .CONTROLS)
				spacer()
				rule(s)
				button(state, "QUIT GAME", "Quit", {kind = .QUIT})
			}
			if clay.UI(clay.ID("Page"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(18 * s)}}) {
				switch state.page {
				case .HOME: home(state, view)
				case .CLASSES: classes(state, view)
				case .SETTINGS: settings(state, view)
				case .CONTROLS: controls(state)
				}
			}
		}
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(24 * s)}, childAlignment = {y = .Center}}}) {
			text("TAB  NAVIGATE     ENTER  SELECT     ESC  BACK", 11, s, MUTED)
			spacer()
			text("WASD  MOVE     SPACE  JUMP     SHIFT  CROUCH", 11, s, MUTED)
		}
	}
	return clay.EndLayout(max(0, delta))
}

home :: proc(state: ^State, view: View) {
	s := state.scale
	class := selected(view)
	if clay.UI(clay.ID("Welcome"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(26 * s)), childGap = u16(12 * s)}}) {
		text(view.active ? "BACK IN THE ACTION" : "JUMP IN. KEEP MOVING.", 13, s, ACCENT)
		text(view.active ? "READY FOR MORE?" : "MAKE YOUR NEXT MOVE.", 48, s)
		text(view.online ? "Your match is live. Choose a class and join the action." : "Practice your movement, learn the maps, find your class.", 17, s, MUTED)
		spacer()
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(24 * s)}}) {
			text(view.map_name, 24, s)
			text(view.mode, 16, s, ACCENT)
		}
		text(fmt.tprintf("%d PLAYER%s IN SESSION", view.player_count, view.player_count == 1 ? "" : "S"), 12, s, MUTED)
	}
	if clay.UI(clay.ID("HomeCards"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(230 * s)}, childGap = u16(18 * s)}}) {
		if clay.UI(clay.ID("LoadoutCard"))({
			layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(24 * s)), childGap = u16(10 * s)},
			backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(8 * s),
		}) {
			text("YOUR NEXT LOADOUT", 12, s, MUTED)
			text(class.name, 26, s)
			text(class.weapon, 16, s, ACCENT)
			spacer()
			button(state, "CHANGE CLASS", "ChangeClass", {index = i32(Page.CLASSES)})
		}
		if clay.UI(clay.ID("PlayCard"))({
			layout = {sizing = {width = clay.SizingFixed(310 * s), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(24 * s)), childGap = u16(10 * s)},
			backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(8 * s),
		}) {
			text(view.online ? "MULTIPLAYER" : "LOCAL PLAY", 12, s, MUTED)
			text(view.active ? "Still in the fight." : "Time to warm up.", 23, s)
			text(view.active ? "Resume your current life." : "Spawn with your selected class.", 14, s, MUTED)
			spacer()
			label := view.spawn_pending ? "JOINING..." : !view.ready ? "WAITING FOR SERVER..." : view.active ? "RESUME" : "PLAY NOW"
			button(state, label, "Play", {kind = .PLAY}, primary = true, enabled = view.ready && !view.spawn_pending)
		}
	}
}

classes :: proc(state: ^State, view: View) {
	s := state.scale
	text("CHOOSE YOUR CLASS", 32, s)
	text("Find your loadout. Changes apply on your next spawn.", 15, s, MUTED)
	if clay.UI(clay.ID("ClassBody"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, childGap = u16(18 * s)}}) {
		if clay.UI(clay.ID("ClassGrid"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = u16(12 * s)}, clip = {vertical = true, childOffset = clay.GetScrollOffset()}}) {
			available: [32]Class
			count := 0
			for class in view.classes {
				if class.available && count < len(available) { available[count] = class; count += 1 }
			}
			columns := state.scale < 0.7 ? 2 : 3
			for row in 0 ..< (count + columns - 1) / columns {
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(125 * s)}, childGap = u16(12 * s)}}) {
					for column in 0 ..< columns {
						index := row * columns + column
						if index >= count {
							if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}}}) {}
							continue
						}
						class := available[index]
						id := clay.ID("Class", u32(class.id))
						register(state, {id = id, enabled = true, action = {kind = .SELECT_CLASS, index = class.id}})
						is_selected := view.selected_class == class.id
						color := is_selected ? SELECTED : SURFACE
						if clay.PointerOver(id) { color = {45, 57, 68, 255} }
						if clay.UI(id)({
							layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(14 * s)), childGap = u16(8 * s)},
							backgroundColor = color, cornerRadius = clay.CornerRadiusAll(5 * s),
							border = {color = ACCENT, width = clay.BorderOutside(state.focus == id.id || is_selected ? 1 : 0)},
						}) {
							text(class.name, 18, s, is_selected ? ACCENT : WHITE)
							spacer()
							text(class.weapon, 12, s, MUTED)
						}
					}
				}
			}
		}
		class := selected(view)
		if clay.UI(clay.ID("ClassDetails"))({
			layout = {sizing = {width = clay.SizingFixed(275 * s), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(22 * s)), childGap = u16(18 * s)},
			backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(8 * s),
		}) {
			text("SELECTED CLASS", 12, s, MUTED)
			text(class.name, 27, s)
			text(class.weapon, 17, s, ACCENT)
			rule(s)
			stat("HEALTH", fmt.tprintf("%d HP", class.health), s)
			stat("SPEED", fmt.tprintf("%d%%", i32(class.speed * 100 + 0.5)), s)
			stat("WALL JUMP", class.wall_jump ? "YES" : "NO", s)
			text(class.wall_jump ? "Release Space, then jump again against a wall to kick away." : "Slide, jump, and air strafe to carry your momentum.", 14, s, MUTED)
			spacer()
			button(state, "BACK TO PLAY", "ClassBack", {index = i32(Page.HOME)})
		}
	}
}

settings :: proc(state: ^State, view: View) {
	s := state.scale
	text("SETTINGS", 32, s)
	text("Make yourself comfortable. Changes take effect immediately.", 15, s, MUTED)
	if clay.UI(clay.ID("SettingsPanel"))({
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(26 * s)), childGap = u16(18 * s)},
		backgroundColor = PANEL, cornerRadius = clay.CornerRadiusAll(8 * s), clip = {vertical = true, childOffset = clay.GetScrollOffset()},
	}) {
		text("DISPLAY MODE", 13, s, MUTED)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(12 * s)}}) {
			labels := [3]string{"WINDOWED", "BORDERLESS", "FULLSCREEN"}
			for label, i in labels {
				button(state, label, "DisplayMode", {kind = .DISPLAY_MODE, index = i32(i)}, view.display_mode == i32(i))
			}
		}
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = u16(12 * s), childAlignment = {y = .Center}}}) {
			text("RESOLUTION", 15, s)
			spacer()
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(55 * s)}}}) { button(state, "<", "ResolutionMinus", {kind = .RESOLUTION, index = -1}) }
			text(view.resolution, 17, s, ACCENT)
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(55 * s)}}}) { button(state, ">", "ResolutionPlus", {kind = .RESOLUTION, index = 1}) }
		}
		rule(s)
		stat("MOUSE SENSITIVITY", fmt.tprintf("%d%%", i32(view.sensitivity * 100 + 0.5)), s)
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
			text("SHOW FPS", 15, s)
			spacer()
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(140 * s)}}}) { button(state, view.show_fps ? "ON" : "OFF", "Fps", {kind = .FPS}, view.show_fps) }
		}
	}
}

controls :: proc(state: ^State) {
	s := state.scale
	text("LEARN THE CONTROLS", 32, s)
	text("Keep your momentum. Every movement counts.", 15, s, MUTED)
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
