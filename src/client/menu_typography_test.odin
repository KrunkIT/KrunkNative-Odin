package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import menuui "../menu"
import clay "../third_party/clay"

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
		classes := [?]menuui.Class{
			{id = 0, name = "Triggerman", weapon = "Assault Rifle", health = 100, speed = 1, available = true},
			{id = 1, name = "Hunter", weapon = "Sniper Rifle", health = 60, speed = 1, available = true},
			{id = 2, name = "Run N Gun", weapon = "Submachine Gun", health = 100, speed = 1, available = true},
		}
		view := menuui.View{classes = classes[:], ready = true, map_name = "Sandstorm", mode = "HARDPOINT", resolution = "1920 x 1080", sensitivity = 1}
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		sizes := [?][2]i32{{1600, 900}, {1280, 720}, {960, 540}}
		for size in sizes {
			glfw.SetWindowSize(window, size[0], size[1])
			glfw.PollEvents()
			gl.Viewport(0, 0, size[0], size[1])
			ui_update(ui, f32(size[0]), f32(size[1]))
			for page in menuui.Page {
				state.page = page
				commands := menuui.build(&state, view, {}, ui.width, ui.height, 1.0 / 60.0)
				testing.expect(t, state.errors == 0, "menu layout reported an error")
				gl.ClearColor(0.17, 0.17, 0.17, 1)
				gl.Clear(gl.COLOR_BUFFER_BIT)
				menu_render_commands(ui, commands)
				labels := [?][2]string{
					{"PLAY", "NavHome"}, {"QUIT GAME", "Quit"},
					{"PLAY NOW", "Play"}, {"PASTE & JOIN LINK", "JoinLink"},
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
				if page == .HOME {
					first := clay.GetElementData(clay.ID("LoadoutCard")).boundingBox
					ids := [?]string{"PlayCard", "JoinCard"}
					for id in ids {
						box := clay.GetElementData(clay.ID(id)).boundingBox
						testing.expect(t, abs(box.width - first.width) < 1 && abs(box.y - first.y) < 1, "home cards must share widths and top alignment")
					}
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
					path := fmt.aprintf("bin/menu_%v_%dx%d.ppm", page, size[0], size[1])
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
