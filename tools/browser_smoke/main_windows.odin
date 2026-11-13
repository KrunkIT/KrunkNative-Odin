package main

import "core:fmt"
import "core:os"
import "core:time"
import access "../../src/browser_access"

// Live IPC/cancellation check. Opens the official page; never prints token contents.
main :: proc() { if !run() { os.exit(1) } }

run :: proc() -> bool {
	child: access.Child
	captcha := len(os.args) == 3 && os.args[1] == "--captcha"
	game := captcha ? os.args[2] : ""
	if captcha && !access.captcha_game_valid(game) { fmt.eprintln("Invalid fixture game ID"); return false }
	if !access.start(&child, 1, false, captcha ? "CAPTCHA" : "", game) { fmt.eprintln("Could not start browser helper"); return false }
	defer access.stop(&child, 1)
	started := time.now()
	cancelled := false
	for time.since(started) < 30*time.Second {
		message, ready, alive := access.receive(child.output, &child.buffer)
		if !alive { if cancelled { fmt.println("Private IPC and browser cancellation passed."); return true }; break }
		if ready {
			defer delete(message.kind); defer delete(message.value)
			if message.kind == "TOKEN" || message.kind == "CAPTCHA" { fmt.eprintln("Unexpected token during cancellation check"); return false }
			if captcha ? message.kind == "TRACE" && message.value == "CAPTCHA_ARMED" : message.kind == "STATUS" && message.value == "VISIBLE" {
				fmt.println(captcha ? "Challenge capture installed before navigation in WebView2; cancelling." : "Visible browser acknowledged request 1.")
				if !access.send(child.input, access.Message{1, "CANCEL", ""}) { break }
				cancelled = true
			}
			if message.kind == "ERROR" {
				if message.value == "CANCELLED" { fmt.println("Private IPC and browser cancellation passed."); return true }
				fmt.eprintln(access.status_text(message.value)); break
			}
		}
		time.sleep(10*time.Millisecond)
	}
	fmt.eprintln("Browser cancellation check failed.")
	return false
}
