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
		context = runtime.default_context()
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
		}
		classes[2].weapon="SMG"
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
			for scenario in 0..<8 {
				view.online=true; view.team_pending=false; view.class_pending=false; view.spawn_pending=false; view.join_status=""; view.active=false
				state.page=.HOME
				view.players=players[:]; view.teams[0].capacity=4; view.teams[1].capacity=4; view.selection_status=""
				switch scenario {
				case 0:
				case 1: view.team_pending=true; view.requested_team=2; view.class_pending=true; view.spawn_pending=true; view.selection_status="Awaiting server confirmation"
				case 2: state.page=.SETTINGS
				case 3: state.page=.SESSION; menuui.set_invite(&state,"https://krunker.io/?game=FRA:long-invite-code")
				case 4: view.online=false; view.join_status="Connection failed. Check your invite and try again."; menuui.set_invite(&state,"")
				case 5: view.active=true
				case 6: state.page=.CONTROLS
				case 7: view.players=full_players[:]; view.teams[0].capacity=16; view.teams[1].capacity=16
				}
				page := state.page
				commands := menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
				testing.expect(t, state.errors == 0, "menu layout reported an error")
				gl.ClearColor(0.17, 0.17, 0.17, 1)
				gl.Clear(gl.COLOR_BUFFER_BIT)
				menu_render_commands(ui, commands)
				labels := [?][2]string{
					{"Quit", "Quit"}, {"Enter Game", "Play"}, {"Respawn", "Play"}, {"Resume", "Play"}, {"Join", "JoinLink"}, {"Paste", "Paste"},
				}
				for command in commands.internalArray[:commands.length] {
					if command.commandType != .Text { continue }
					text := command.renderData.text.stringContents
					for label in labels {
						if string(text.chars[:text.length]) != label[0] { continue }
						parent := clay.GetElementData(clay.ID(label[1]))
						box := command.boundingBox
						testing.expect(t, parent.found && box.x >= parent.boundingBox.x && box.y >= parent.boundingBox.y &&
							box.x + box.width <= parent.boundingBox.x + parent.boundingBox.width &&
							box.y + box.height <= parent.boundingBox.y + parent.boundingBox.height,
							"actual font label must fit inside its button")
					}
				}
				if page == .HOME && view.online {
					left := clay.GetElementData(clay.ID("Team",1)).boundingBox
					right := clay.GetElementData(clay.ID("Team",2)).boundingBox
					play := clay.GetElementData(clay.ID("Play")).boundingBox
					if scenario==0 { play_y=play.y }
					testing.expect(t, abs(play.y-play_y)<1, "Play must stay fixed when selections are pending")
					testing.expect(t, abs(left.width-right.width)<1 && abs(left.y-right.y)<1, "team panels must have equal widths and top alignment")
					testing.expect(t, play.x >= left.x+left.width && play.x+play.width <= right.x, "Play must sit between the rosters")
				}
				when #config(MENU_PREVIEW, false) {
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
			}
		}
	}
}
