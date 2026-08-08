#+build !windows

package server_main

// POSIX and Apple timers already deliver sub-millisecond sleeps, so no timer
// resolution change is needed on non-Windows platforms.
server_set_timer_precision :: proc() {
}

server_restore_timer_precision :: proc() {
}
