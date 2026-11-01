package main

import "core:c"
import "core:fmt"
import "core:strings"
import "core:time"
import curl "vendor:curl"
import krunker "../../src/krunker"

test_local_websocket :: proc(base: string) -> bool {
	handle := curl.easy_init()
	if handle == nil do return false
	defer curl.easy_cleanup(handle)
	url := strings.clone_to_cstring(fmt.tprintf("ws://%s/ws", base[len("http://"):]))
	defer delete(url)
	curl.easy_setopt(handle, .URL, url)
	curl.easy_setopt(handle, .CONNECT_ONLY, c.long(2))
	curl.easy_setopt(handle, .TIMEOUT_MS, c.long(3000))
	if code := curl.easy_perform(handle); code != .E_OK { fmt.eprintln("Mock WebSocket upgrade failed:", code); return false }
	assembly: krunker.Krunker_WS_Message
	defer delete(assembly.buffer)
	buffer: [4096]byte
	reads := 0
	started := time.now()
	for time.duration_seconds(time.since(started)) < 3 {
		received: c.size_t
		meta: ^curl.ws_frame
		code := curl.ws_recv(handle, rawptr(&buffer[0]), c.size_t(len(buffer)), &received, &meta)
		if code == .E_AGAIN { time.sleep(time.Millisecond); continue }
		if code != .E_OK || meta == nil { fmt.eprintln("Mock WebSocket receive failed:", code); return false }
		if (meta.flags & (curl.WS_PING | curl.WS_PONG)) != {} { continue }
		reads += 1
		payload, complete, err := krunker.krunker_ws_message_feed(&assembly, buffer[:int(received)], i64(meta.offset), i64(meta.bytesleft), (meta.flags & curl.WS_CONT) != {})
		if len(err) > 0 { fmt.eprintln("Mock WebSocket reassembly failed:", err); return false }
		if !complete do continue
		messages, _, decode_error := krunker.krunker_msgpack_decode_packet(payload)
		if len(decode_error) > 0 || len(messages) != 1 { fmt.eprintln("Mock complete message decode failed:", decode_error); return false }
		packet := messages[0].([]krunker.Krunker_Msgpack_Value)
		blob := packet[1].(string)
		if len(payload) != 52007 || packet[0].(i64) != 0 || len(blob) != 52000 || reads < 2 { fmt.eprintln("Mock WebSocket message content was not preserved"); return false }
		fmt.println("Real libcurl chunked/fragmented WebSocket with interleaved ping OK")
		return true
	}
	fmt.eprintln("Mock WebSocket reassembly timed out")
	return false
}
