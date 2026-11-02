#+build !windows

package main

import glfw "vendor:glfw"
import shared "../shared"

client_mouse_init :: proc(window: glfw.WindowHandle) -> bool { return false }
client_mouse_fini :: proc() {}
client_mouse_delta :: proc(fallback: shared.Vec2) -> shared.Vec2 { return fallback }
client_poll_events :: proc() { glfw.PollEvents() }
