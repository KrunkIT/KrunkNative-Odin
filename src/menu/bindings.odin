package menu

import "core:fmt"

Binding_Action :: enum { FORWARD, BACKWARD, LEFT, RIGHT, JUMP, CROUCH, AIM, FIRE, RELOAD, SECONDARY, MELEE, MENU, FULLSCREEN }
// Positive values are portable GLFW key codes. Mouse buttons use -(button+1).
// Zero means unbound; neither the menu nor saved preferences store OS scancodes.
Bindings :: [Binding_Action][2]i32
BINDING_NAMES := [Binding_Action]string{
	.FORWARD = "Forward", .BACKWARD = "Backward", .LEFT = "Left", .RIGHT = "Right", .JUMP = "Jump", .CROUCH = "Crouch / slide",
	.AIM = "Aim down sights", .FIRE = "Fire", .RELOAD = "Reload", .SECONDARY = "Secondary / primary", .MELEE = "Melee / primary", .MENU = "Menu / resume", .FULLSCREEN = "Fullscreen",
}

default_bindings :: proc() -> Bindings {
	return {.FORWARD = {'W', 0}, .BACKWARD = {'S', 0}, .LEFT = {'A', 0}, .RIGHT = {'D', 0}, .JUMP = {32, 0}, .CROUCH = {340, 0},
		.AIM = {-2, 0}, .FIRE = {-1, 0}, .RELOAD = {'R', 0}, .SECONDARY = {'E', 0}, .MELEE = {'Q', 0}, .MENU = {256, 0}, .FULLSCREEN = {300, 0}}
}

binding_valid :: proc(code: i32) -> bool {
	return code == 0 || (code >= -8 && code <= -1) || code == 32 || code == 39 || (code >= 44 && code <= 57) || code == 59 || code == 61 ||
		(code >= 65 && code <= 93) || code == 161 || code == 162 || (code >= 256 && code <= 269) ||
		(code >= 280 && code <= 284) || (code >= 290 && code <= 314) || (code >= 320 && code <= 336) || (code >= 340 && code <= 348)
}

binding_label :: proc(code: i32) -> string {
	if (code >= 'A' && code <= 'Z') || (code >= '0' && code <= '9') { return fmt.tprintf("%c", rune(code)) }
	if code >= 290 && code <= 314 { return fmt.tprintf("F%d", code-289) }
	if code >= 320 && code <= 329 { return fmt.tprintf("Numpad %d", code-320) }
	switch code {
	case 0: return "Unbound"
	case -1: return "Left Mouse"
	case -2: return "Right Mouse"
	case -3: return "Middle Mouse"
	case -4, -5, -6, -7, -8: return fmt.tprintf("Mouse %d", -code)
	case 32: return "Space"
	case 39: return "'"
	case 44: return ","
	case 45: return "-"
	case 46: return "."
	case 47: return "/"
	case 59: return ";"
	case 61: return "="
	case 91: return "["
	case 92: return "\\"
	case 93: return "]"
	case 256: return "Escape"
	case 257: return "Enter"
	case 258: return "Tab"
	case 259: return "Backspace"
	case 260: return "Insert"
	case 261: return "Delete"
	case 262: return "Right Arrow"
	case 263: return "Left Arrow"
	case 264: return "Down Arrow"
	case 265: return "Up Arrow"
	case 266: return "Page Up"
	case 267: return "Page Down"
	case 268: return "Home"
	case 269: return "End"
	case 280: return "Caps Lock"
	case 281: return "Scroll Lock"
	case 282: return "Num Lock"
	case 283: return "Print Screen"
	case 284: return "Pause"
	case 330: return "Numpad ."
	case 331: return "Numpad /"
	case 332: return "Numpad *"
	case 333: return "Numpad -"
	case 334: return "Numpad +"
	case 335: return "Numpad Enter"
	case 336: return "Numpad ="
	case 340: return "Left Shift"
	case 341: return "Left Ctrl"
	case 342: return "Left Alt"
	case 343: return "Left Super"
	case 344: return "Right Shift"
	case 345: return "Right Ctrl"
	case 346: return "Right Alt"
	case 347: return "Right Super"
	case 348: return "Menu Key"
	}
	return fmt.tprintf("Key %d", code)
}
