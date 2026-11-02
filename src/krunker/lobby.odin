package krunker

import "core:strings"

Krunker_Lobby_Player :: struct {
	id, name: string,
	team, class_index: i32,
	active: bool,
}

krunker_lobby_clear :: proc(state: ^Krunker_World_State) {
	for player in state.lobby_players { delete(player.id); delete(player.name) }
	clear(&state.lobby_players)
}

krunker_lobby_record :: proc(state: ^Krunker_World_State, id: string, value: Krunker_Msgpack_Value) -> bool {
	index := -1
	for player, i in state.lobby_players { if player.id == id { index = i; break } }
	if _, removed := value.(Krunker_Msgpack_Nil); removed {
		if index >= 0 {
			delete(state.lobby_players[index].id)
			delete(state.lobby_players[index].name)
			ordered_remove(&state.lobby_players, index)
		}
		return true
	}
	entries, ok := value.([]Krunker_Msgpack_Map_Entry)
	if !ok { return false }
	if index < 0 {
		append(&state.lobby_players, Krunker_Lobby_Player{id = strings.clone(id), class_index = -1})
		index = len(state.lobby_players)-1
	}
	player := &state.lobby_players[index]
	// cda replaces the complete record. A team change can remove its class.
	delete(player.name)
	player^ = Krunker_Lobby_Player{id = player.id, class_index = -1}
	for entry in entries {
		key, textual := entry.key.(string); if !textual { continue }
		switch key {
		case "t": player.team = krunker_world_i32(entry.value, player.team)
		case "c": player.class_index = krunker_world_i32(entry.value, -1)
		case "a": player.active = krunker_world_bool(entry.value)
		case "n":
			if name, named := entry.value.(string); named { delete(player.name); player.name = strings.clone(name) }
		}
	}
	return true
}

// cd is the full pre-spawn lobby roster; cda changes one lobby assignment.
// Connection UIDs identify these records; io-init socket IDs identify players
// in simulation packets and are a separate namespace.
krunker_world_apply_lobby :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	opcode, _ := packet[0].(string)
	if opcode == "cd" {
		entries, ok := packet[1].([]Krunker_Msgpack_Map_Entry); if !ok { return false }
		krunker_lobby_clear(state)
		for entry in entries {
			if id, valid := entry.key.(string); valid { krunker_lobby_record(state, id, entry.value) }
		}
		return true
	}
	if opcode == "cda" && len(packet) > 2 {
		if id, valid := packet[1].(string); valid { return krunker_lobby_record(state, id, packet[2]) }
	}
	return false
}
