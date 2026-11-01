package krunker

// libcurl may return one WebSocket frame over many reads. A message can also
// span several frames. Only the completed message has a MessagePack trailer.
Krunker_WS_Message :: struct {
	buffer: [dynamic]byte,
	message_open: bool,
	frame_open: bool,
	next_offset: i64,
}

krunker_ws_message_reset :: proc(state: ^Krunker_WS_Message) {
	clear(&state.buffer)
	state.message_open = false
	state.frame_open = false
	state.next_offset = 0
}

// Returned bytes borrow state.buffer until the next call. Control frames must
// be handled separately, without changing the partially assembled message.
krunker_ws_message_feed :: proc(state: ^Krunker_WS_Message, chunk: []byte, offset, bytesleft: i64, more_frames: bool) -> (payload: []byte, complete: bool, error: string) {
	if offset < 0 || bytesleft < 0 { krunker_ws_message_reset(state); return nil, false, "negative WebSocket frame metadata" }
	if offset == 0 {
		if state.frame_open { krunker_ws_message_reset(state); return nil, false, "new WebSocket frame before previous frame completed" }
		if !state.message_open { clear(&state.buffer); state.message_open = true }
		state.frame_open = true
		state.next_offset = 0
	}
	if !state.frame_open || offset != state.next_offset { krunker_ws_message_reset(state); return nil, false, "WebSocket frame offset is not contiguous" }
	remaining := KRUNKER_MSGPACK_MAX_BYTES + 2 - len(state.buffer)
	if len(chunk) > remaining || bytesleft > i64(remaining - len(chunk)) { krunker_ws_message_reset(state); return nil, false, "WebSocket message exceeds 16 MiB limit" }
	append(&state.buffer, ..chunk)
	state.next_offset += i64(len(chunk))
	if bytesleft > 0 do return nil, false, ""
	state.frame_open = false
	state.next_offset = 0
	if more_frames do return nil, false, ""
	state.message_open = false
	return state.buffer[:], true, ""
}
