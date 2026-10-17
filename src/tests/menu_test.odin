package main

import "core:fmt"
import menuui "../menu"
import clay "../third_party/clay"
import shared "../shared"

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
		weapon := "No primary weapon"
		if len(class.loadout) > 0 && class.loadout[0] >= 0 && int(class.loadout[0]) < len(shared.WEAPONS_LIST) && shared.WEAPONS_LIST[class.loadout[0]] != nil {
			weapon = shared.WEAPONS_LIST[class.loadout[0]].name
		}
		classes[i] = {id = i32(i), name = class.name, weapon = weapon, health = class.health, speed = class.speed, wall_jump = class.wall_jump, available = shared.class_is_in_rotation(i32(i))}
	}
	view := menuui.View{classes = classes[:], ready = true, selected_class = 2, map_name = "Sandstorm", mode = "HARDPOINT", resolution = "1280 x 720", sensitivity = 1}
	// Real Clay layout and linkage, at common and smaller window sizes.
	sizes := [3][2]f32{{1280, 720}, {1920, 1080}, {960, 540}}
	for size in sizes {
		for page in menuui.Page {
			state.page = page
			commands := menuui.build(&state, view, {}, size[0], size[1], PHYSICS_DT)
			if commands.length == 0 || state.errors != 0 { fmt.eprintln("Menu layout/ABI test failed"); return false }
			ids := [2]string{"Sidebar", "Page"}
			for id in ids {
				data := clay.GetElementData(clay.ID(id))
				box := data.boundingBox
				if !data.found || box.x < 0 || box.y < 0 || box.width <= 0 || box.height <= 0 || box.x + box.width > size[0] + 1 || box.y + box.height > size[1] + 1 {
					fmt.printf("Menu bounds test failed: page=%v size=%v element=%s box=%v\n", page, size, id, box)
					return false
				}
			}
		}
	}
	state.page = .HOME
	menu_test_frame(&state, view, {})
	if menu_test_frame(&state, view, {pointer = {1270, 710}, down = true}).kind != .NONE || menu_test_frame(&state, view, {pointer = {1270, 710}}).kind != .NONE { return false }
	// Release outside cancels; a complete click inside activates Play.
	box := clay.GetElementData(clay.ID("Play")).boundingBox
	menu_test_frame(&state, view, {pointer = {box.x + 5, box.y + 5}, down = true})
	if menu_test_frame(&state, view, {pointer = {1270, 710}}).kind != .NONE { return false }
	if menu_test_click(&state, view, clay.ID("Play")).kind != .PLAY { fmt.eprintln("Menu play click failed"); return false }
	view.ready = false
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("Play")).kind != .NONE { return false }
	view.ready = true
	menu_test_frame(&state, view, {})
	menu_test_click(&state, view, clay.ID("NavClasses", u32(menuui.Page.CLASSES)))
	menu_test_frame(&state, view, {})
	if state.page != .CLASSES || menu_test_click(&state, view, clay.ID("Class", 2)).index != 2 { return false }
	menu_test_frame(&state, view, {escape = true})
	if state.page != .HOME { return false }
	// Tab/Enter navigation shares the same controls as mouse interaction.
	menu_test_frame(&state, view, {})
	state.focus = clay.ID("Play").id
	if menu_test_frame(&state, view, {enter = true}).kind != .PLAY { return false }
	menu_test_frame(&state, view, {})
	state.focus = 0
	menu_test_frame(&state, view, {tab = true})
	if state.focus == 0 { return false }
	state.page = .SETTINGS
	menu_test_frame(&state, view, {})
	box = clay.GetElementData(clay.ID("Sensitivity")).boundingBox
	input := menuui.Input{pointer = {box.x + box.width * 0.75, box.y + box.height / 2}, down = true}
	value := menu_test_frame(&state, view, input)
	if value.kind != .SENSITIVITY || abs(value.value - 1.525) > 0.001 { return false }
	input.pointer[0] = box.x + box.width + 20
	if menu_test_frame(&state, view, input).value != 2 { return false }
	menu_test_frame(&state, view, {})
	if state.page != .SETTINGS { return false }
	state.focus = clay.ID("Sensitivity").id
	value = menu_test_frame(&state, view, {right = true})
	if value.kind != .SENSITIVITY || abs(value.value - 1.05) > 0.001 { return false }
	fmt.println("Clay menu layout/mouse/keyboard/slider tests OK")
	return state.errors == 0
}
