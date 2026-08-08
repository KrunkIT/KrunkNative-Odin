package server_main

import win "core:sys/windows"

server_set_timer_precision :: proc() {
	// Raise the Windows timer resolution to ~1 ms so time.sleep() does not
	// round every pause up to the default ~15.6 ms quantum.
	win.timeBeginPeriod(1)
}

server_restore_timer_precision :: proc() {
	win.timeEndPeriod(1)
}
