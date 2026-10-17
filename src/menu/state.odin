package menu

import "core:fmt"
import "base:runtime"
import clay "../third_party/clay"

Page :: enum { HOME, CLASSES, SETTINGS, CONTROLS }
Action_Kind :: enum { NONE, PLAY, QUIT, SELECT_CLASS, DISPLAY_MODE, RESOLUTION, SENSITIVITY, FPS }
Action :: struct { kind: Action_Kind, index: i32, value: f32 }
Class :: struct { id: i32, name, weapon: string, health: i32, speed: f32, wall_jump, available: bool }
View :: struct {
	classes: []Class,
	selected_class: i32,
	online, active, spawn_pending, ready: bool,
	map_name, mode, resolution: string,
	player_count: int,
	display_mode: i32,
	sensitivity: f32,
	show_fps: bool,
}
Input :: struct {
	pointer: clay.Vector2,
	down, tab, shift, enter, escape, left, right: bool,
	scroll: clay.Vector2,
}
Control :: struct { id: clay.ElementId, action: Action, enabled, slider: bool }
State :: struct {
	page: Page,
	ctx: ^clay.Context,
	memory: []u8,
	controls: [64]Control,
	control_count: int,
	focus, pressed: u32,
	previous: Input,
	scale: f32,
	errors: int,
}

error_handler :: proc "c" (data: clay.ErrorData) {
	context = runtime.default_context()
	state := cast(^State)data.userData
	state.errors += 1
	fmt.eprintf("[Menu] %s\n", string(data.errorText.chars[:data.errorText.length]))
}

init :: proc(state: ^State, measure: proc "c" (clay.StringSlice, ^clay.TextElementConfig, rawptr) -> clay.Dimensions, user: rawptr) -> bool {
	clay.SetMaxElementCount(2048)
	clay.SetMaxMeasureTextCacheWordCount(4096)
	state.memory = make([]u8, int(clay.MinMemorySize()))
	arena := clay.CreateArenaWithCapacityAndMemory(uint(len(state.memory)), raw_data(state.memory))
	state.ctx = clay.Initialize(arena, {1280, 720}, {handler = error_handler, userData = state})
	clay.SetMeasureTextFunction(measure, user)
	return state.ctx != nil && state.errors == 0
}

fini :: proc(state: ^State) {
	if clay.GetCurrentContext() == state.ctx { clay.SetCurrentContext(nil) }
	delete(state.memory)
	state.memory = nil
	state.ctx = nil
}

contains :: proc(box: clay.BoundingBox, point: clay.Vector2) -> bool {
	return point[0] >= box.x && point[1] >= box.y && point[0] < box.x + box.width && point[1] < box.y + box.height
}

register :: proc(state: ^State, control: Control) {
	assert(state.control_count < len(state.controls))
	state.controls[state.control_count] = control
	state.control_count += 1
}

// Resolve interactions after layout, against this frame's actual rectangles.
// Pointer press captures a control; release activates it only over that control.
interact :: proc(state: ^State, input: Input, view: View) -> Action {
	clay.SetCurrentContext(state.ctx)
	clay.SetPointerState(input.pointer, input.down)
	defer state.previous = input
	focused_index := -1
	for control, i in state.controls[:state.control_count] {
		if control.id.id == state.focus && control.enabled { focused_index = i }
	}
	if input.escape && !state.previous.escape {
		state.pressed = 0
		if state.page != .HOME {
			state.page = .HOME
			state.focus = 0
		} else if view.active {
			return {kind = .PLAY}
		}
		return {}
	}
	if input.tab && !state.previous.tab {
		step := input.shift ? -1 : 1
		if focused_index < 0 { focused_index = input.shift ? 0 : -1 }
		for _ in 0 ..< state.control_count {
			focused_index = (focused_index + step + state.control_count) % state.control_count
			if state.controls[focused_index].enabled {
				state.focus = state.controls[focused_index].id.id
				focus_visible(state.controls[focused_index], state.page)
				break
			}
		}
	}
	if input.enter && !state.previous.enter && focused_index >= 0 {
		control := state.controls[focused_index]
		if !control.slider { return activate(state, control) }
	}
	if focused_index >= 0 && state.controls[focused_index].slider {
		direction := (input.right && !state.previous.right ? 1 : 0) - (input.left && !state.previous.left ? 1 : 0)
		if direction != 0 { return {kind = .SENSITIVITY, value = clamp(view.sensitivity + f32(direction) * 0.05, 0.1, 2)} }
	}
	for control in state.controls[:state.control_count] {
		if !control.enabled { continue }
		data := clay.GetElementData(control.id)
		over := data.found && contains(data.boundingBox, input.pointer) && clay.PointerOver(control.id)
		if input.down && !state.previous.down && over {
			state.pressed = control.id.id
			state.focus = control.id.id
		}
		if state.pressed == control.id.id {
			if control.slider && input.down {
				progress := clamp((input.pointer[0] - data.boundingBox.x) / data.boundingBox.width, 0, 1)
				return {kind = .SENSITIVITY, value = 0.1 + progress * 1.9}
			}
			if !input.down && state.previous.down && over {
				state.pressed = 0
				if control.slider { return {} }
				return activate(state, control)
			}
		}
	}
	if !input.down { state.pressed = 0 }
	return {}
}

activate :: proc(state: ^State, control: Control) -> Action {
	// Navigation changes the menu page without dispatching a gameplay action.
	if control.action.kind == .NONE {
		state.page = Page(control.action.index)
		state.focus = 0
		return {}
	}
	return control.action
}

focus_visible :: proc(control: Control, page: Page) {
	container: string
	if page == .CLASSES && control.action.kind == .SELECT_CLASS { container = "ClassGrid" }
	if page == .SETTINGS && (control.slider || control.action.kind == .DISPLAY_MODE || control.action.kind == .RESOLUTION || control.action.kind == .FPS) { container = "SettingsPanel" }
	if len(container) == 0 { return }
	data := clay.GetScrollContainerData(clay.ID(container))
	if !data.found { return }
	parent := clay.GetElementData(clay.ID(container)).boundingBox
	box := clay.GetElementData(control.id).boundingBox
	offset: f32
	if box.y < parent.y { offset = parent.y - box.y }
	if box.y + box.height > parent.y + parent.height { offset = parent.y + parent.height - box.y - box.height }
	data.scrollPosition[1] = clamp(data.scrollPosition[1] + offset, min(0, data.scrollContainerDimensions.height - data.contentDimensions.height), 0)
}
