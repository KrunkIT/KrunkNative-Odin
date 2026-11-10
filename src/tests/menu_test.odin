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
	menu_test_click(&state, view, clay.ID("Settings",u32(menuui.Page.SETTINGS)))
	menu_test_frame(&state, view, {})
	if state.page != .SETTINGS { return false }
	// Lobby controls cannot activate through an overlay.
	if menu_test_click(&state, view, clay.ID("Play")).kind != .NONE { return false }
	menu_test_frame(&state, view, {})
	box = clay.GetElementData(clay.ID("Sensitivity")).boundingBox
	input := menuui.Input{pointer={box.x+box.width*0.75,box.y+box.height/2},down=true}
	value := menu_test_frame(&state, view, input)
	if value.kind != .SENSITIVITY || abs(value.value-1.525)>0.001 { return false }
	menu_test_frame(&state, view, {})
	state.focus = clay.ID("Sensitivity").id
	value = menu_test_frame(&state, view, {right=true})
	if value.kind != .SENSITIVITY || abs(value.value-1.05)>0.001 { return false }
	// Audio sliders retain their own channel and range when using the keyboard.
	view.audio_volumes = {0.8, 1, 0.5, 0}
	for name, i in ([4]string{"MasterVolume", "EffectsVolume", "FootstepsVolume", "UiVolume"}) {
		menu_test_frame(&state, view, {})
		state.focus = clay.ID(name).id
		value = menu_test_frame(&state, view, {right = true})
		if value.kind != .AUDIO_VOLUME || value.index != i32(i) || abs(value.value - min(1, view.audio_volumes[i]+0.05)) > 0.001 {
			fmt.println("Audio slider keyboard routing failed", name, value); return false
		}
	}
	// Tab scrolls focused audio controls into view; dragging adjusts that channel.
	menu_test_frame(&state, view, {})
	state.focus = clay.ID("FootstepsVolume").id
	menu_test_frame(&state, view, {tab = true})
	menu_test_frame(&state, view, {})
	box = clay.GetElementData(clay.ID("UiVolume")).boundingBox
	value = menu_test_frame(&state, view, {pointer = {box.x+box.width*0.25, box.y+box.height/2}, down = true})
	if value.kind != .AUDIO_VOLUME || value.index != 3 || abs(value.value-0.25)>0.001 { fmt.println("Audio slider dragging failed", value); return false }
	menu_test_frame(&state, view, {})
	view.active = true
	if menu_test_frame(&state, view, {escape=true}).kind != .NONE || state.page != .HOME { return false }
	menu_test_frame(&state, view, {})
	if menu_test_frame(&state, view, {escape=true}).kind != .PLAY { return false }
	// Offline connection screen: editable invite, paste, join, and errors.
	view.online=false; view.active=false; view.local_practice=false
	view.join_status="Connection failed. Please check the invite and try again."
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("JoinLink")).kind != .NONE { return false }
	menu_test_click(&state, view, clay.ID("Invite"))
	menu_test_frame(&state, view, {text="krunk://localhost:21015"})
	if menuui.invite(&state) != "krunk://localhost:21015" { return false }
	menu_test_frame(&state, view, {})
	if menu_test_click(&state, view, clay.ID("JoinLink")).kind != .JOIN_LINK { return false }
	// Opening session from the connection screen must not duplicate field IDs.
	state.page=.SESSION
	menu_test_frame(&state, view, {})
	if state.errors != 0 { return false }
	fmt.println("Competitive lobby layout, modal, selection, invite, mouse and keyboard tests OK")
	return test_standard_menu() && test_lobby_packets() && test_live_lobby_records()
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
