package server_main

import "core:fmt"
import "core:net"
import shared "../shared"

Net_Client :: struct {
	id:         u32,
	socket:     net.TCP_Socket,
	active:     bool,
	joined:     bool,
	player:     ^shared.Player,
	pending_input: shared.Input,
	has_pending_input: bool,
	initial_match_sent: bool,
	recv_buffer: [4096]byte,
	recv_len:    int,
	send_queue:  shared.Net_Send_Queue,
}

Net_Server :: struct {
	listener: net.TCP_Socket,
	clients:  [dynamic]^Net_Client,
	next_id:  u32,
}

net_server_flush :: proc(client: ^Net_Client) -> bool {
	if client == nil || !client.active {
		return false
	}

	for {
		pending := shared.net_send_queue_pending(&client.send_queue)
		if len(pending) == 0 {
			return true
		}

		count, err := net.send_tcp(client.socket, pending)
		shared.net_send_queue_consume(&client.send_queue, count)

		if err != nil {
			if err == .Would_Block || err == .Timeout {
				return true
			}
			return false
		}
		if count == 0 {
			return false
		}
	}
}

net_server_send :: proc(client: ^Net_Client, data: []byte) -> bool {
	if client == nil || !client.active || len(data) == 0 {
		return false
	}
	if !shared.net_send_queue_push(&client.send_queue, data) {
		fmt.printf("[Net Server] Client #%d send queue overflow\n", client.id)
		return false
	}
	return net_server_flush(client)
}

net_server_init :: proc(port: int) -> (ns: Net_Server, ok: bool) {
	endpoint := net.Endpoint {
		address = net.IP4_Any,
		port    = port,
	}

	listener, err := net.listen_tcp(endpoint)
	if err != nil {
		fmt.eprintf("Failed to listen on port %d: %v\n", port, err)
		return ns, false
	}

	ns.listener = listener
	ns.next_id = 1
	fmt.printf("Odin TCP Socket Server listening on 0.0.0.0:%d\n", port)
	return ns, true
}

// net_server_drop_client tears down a client that has left: the player is
// removed from the authoritative sim (so the client never sees a ghost) and
// the Net_Client record is freed. Callers must also remove the pointer from
// ns.clients.
net_server_drop_client :: proc(ns: ^Net_Server, game: ^shared.Game, client: ^Net_Client) {
	client.active = false
	if client.player != nil {
		if client.joined {
			shared.game_players_remove(game, client.player)
		}
		shared.player_destroy(client.player)
		client.player = nil
	}
	net.close(client.socket)
	free(client)
}

net_server_poll :: proc(ns: ^Net_Server, game: ^shared.Game) {
	// Poll for new client connections (non-blocking accept check)
	net.set_blocking(ns.listener, false)
	client_socket, _, err := net.accept_tcp(ns.listener)
	if err == nil {
		net.set_blocking(client_socket, false)
		// Tiny per-player snapshots must not sit in the Nagle buffer while the
		// peer's delayed ACK (40 ms on Windows) holds them back.
		net.set_option(client_socket, .TCP_Nodelay, true)

		client := new(Net_Client)
		client.id = ns.next_id
		ns.next_id += 1
		client.socket = client_socket
		client.active = true
		client.player = shared.player_init(game)
		client.player.uid = i32(client.id)

		append(&ns.clients, client)
		fmt.printf("[Net Server] Client #%d connected!\n", client.id)
	}

	// Poll incoming data for each client. Dropped clients are removed in place
	// (the swapped-in last element is re-examined), so the loop stays safe.
	i := 0
	for i < len(ns.clients) {
		client := ns.clients[i]

		if client.active {
			if !net_server_flush(client) {
				fmt.printf("[Net Server] Client #%d send error\n", client.id)
				client.active = false
			}
		}

		if client.active {
			available := client.recv_buffer[client.recv_len:]
			bytes_read, read_err := net.recv_tcp(client.socket, available)

			if bytes_read > 0 {
				client.recv_len += bytes_read
				for client.recv_len >= shared.PACKET_HEADER_SIZE {
					header, h_ok := shared.packet_deserialize_header(client.recv_buffer[:client.recv_len])
					if !h_ok {
						client.active = false
						break
					}
					packet_size := shared.PACKET_HEADER_SIZE + int(header.payload_len)
					if packet_size > len(client.recv_buffer) {
						client.active = false
						break
					}
					if client.recv_len < packet_size {
						break
					}
					packet := client.recv_buffer[:packet_size]
					#partial switch header.packet_type {
					case .CONNECT:
						if class_id, version, connect_ok := shared.packet_deserialize_connect(packet); connect_ok && version == shared.PROTOCOL_VERSION && class_id >= 0 && class_id < i32(len(game.classes)) && client.player != nil {
							if !client.joined {
								shared.game_players_add(game, client.player)
							}
							shared.player_spawn(client.player, class_id)
							client.joined = true
							fmt.printf("[Net Server] Client #%d spawned as class %d on team %d\n", client.id, class_id, client.player.team)
						} else if connect_ok && version != shared.PROTOCOL_VERSION {
							fmt.printf("[Net Server] Client #%d protocol mismatch (client %d, server %d)\n", client.id, version, shared.PROTOCOL_VERSION)
							client.active = false
						}
					case .PLAYER_INPUT:
						if input, input_ok := shared.packet_deserialize_input(packet); input_ok && client.player != nil && client.player.active {
							pending_swap := client.pending_input.swap
							client.pending_input = input

							if input.swap == 0 && pending_swap != 0 {
								client.pending_input.swap = pending_swap
							}

							client.player.input_seq = input.seq
							client.has_pending_input = true
						}
					case .DISCONNECT:
						client.active = false
						fmt.printf("[Net Server] Client #%d requested disconnect\n", client.id)
					}

					client.recv_len -= packet_size
					if client.recv_len > 0 {
						copy(client.recv_buffer[:client.recv_len], client.recv_buffer[packet_size:packet_size + client.recv_len])
					}
				}
			} else if read_err == nil {
				// 0 bytes with no error is a graceful FIN from the peer.
				fmt.printf("[Net Server] Client #%d closed the connection\n", client.id)
				client.active = false
			} else if read_err != .Would_Block && read_err != .Timeout {
				// Reset/closed/invalid socket: the peer vanished without a
				// DISCONNECT packet. Marking it dead here stops the server from
				// broadcasting to (and leaking) a ghost client forever.
				fmt.printf("[Net Server] Client #%d dropped (recv error %v)\n", client.id, read_err)
				client.active = false
			}
		}

		if !client.active {
			net_server_drop_client(ns, game, client)
			unordered_remove(&ns.clients, i)
			continue
		}
		i += 1
	}
}

net_server_queue_inputs :: proc(ns: ^Net_Server, tick_delta: f32) {
	for client in ns.clients {
		if !client.active || !client.has_pending_input || client.player == nil {
			continue
		}
		if !client.player.active {
			client.has_pending_input = false
			continue
		}
		client.pending_input.delta = tick_delta
		client.player.input_seq = client.pending_input.seq
		shared.player_queue_input(client.player, &client.pending_input)
		// Movement/look/fire/scope are held control state and must be sampled on
		// every server tick. Consume only one-shot weapon switching.
		client.pending_input.swap = 0
	}
}

net_server_broadcast_match :: proc(ns: ^Net_Server, game: ^shared.Game) {
	state := shared.packet_match_state_from_game(game)
	state.send_rate = f32(game.config.tick_rate) / f32(shared.SNAPSHOT_RATE_DIVISOR)
	// Largest packet here is MATCH_STATE with a full roster: 7 header + 42 + 32*4.
	match_buf: [256]byte
	match_size := shared.packet_serialize_match_state(match_buf[:], &state)
	if match_size == 0 {
		return
	}
	player_buf: [shared.PACKET_HEADER_SIZE + shared.PACKET_PLAYER_STATE_PAYLOAD_SIZE]byte
	impact_buf: [shared.PACKET_HEADER_SIZE + shared.PACKET_BULLET_IMPACT_PAYLOAD_SIZE]byte

	for client in ns.clients {
		if !client.active {
			continue
		}
		if !client.joined {
			if client.initial_match_sent {
				continue
			}
		}
		// Keep the match frame immutable across recipients. Player snapshots are
		// recipient-specific (`is_you`) and use a separate serialization buffer.
		if !net_server_send(client, match_buf[:match_size]) {
			client.active = false
			continue
		}
		client.initial_match_sent = true
		if !client.joined {
			continue
		}

		for player in game.players {
			weapon_id: u8
			active_ammo: u32
			if player.loadout_index >= 0 && player.loadout_index < player.loadout_size {
				weapon_id = u8(player.loadout[player.loadout_index])
				active_ammo = player.ammo[player.loadout_index]
			}
			player_state := shared.Packet_Player_State{
				player_id = u32(player.uid),
				active = player.active,
				is_you = player == client.player,
				team = player.team,
				class_id = player.class_index,
				position = player.position,
				velocity = player.velocity,
				x_dir = player.direction.x,
				y_dir = player.direction.y,
				on_ground = player.on_ground,
				on_ladder = player.on_ladder,
				on_ramp = player.on_ramp,
				on_terrain = player.on_terrain,
				terrain_slipping = player.terrain_slipping,
				did_jump = player.did_jump,
				did_wall_jump = player.did_wall_jump,
				can_slide = player.can_slide,
				on_wall = player.on_wall,
				crouch_val = player.crouch_val,
				aim_val = player.aim_val,
				slide_timer = player.slide_timer,
				jump_timer = player.jump_timer,
				health = player.health,
				max_health = player.max_health,
				weapon_id = weapon_id,
				active_ammo = active_ammo,
				shot_seq = player.shot_seq,
				ack_seq = player.input_seq,
			}
			state_size := shared.packet_serialize_state(player_buf[:], &player_state)
			if state_size > 0 {
				if !net_server_send(client, player_buf[:state_size]) {
					client.active = false
					break
				}
			}
		}
		if !client.active {
			continue
		}
		for &impact in game.impacts {
			impact_size := shared.packet_serialize_bullet_impact(impact_buf[:], &impact)
			if impact_size > 0 && !net_server_send(client, impact_buf[:impact_size]) {
				client.active = false
				break
			}
		}
	}
	// Impacts are reliable TCP events. Once every active joined client has had
	// them queued, retain only new impacts generated before the next snapshot.
	clear(&game.impacts)
}

net_server_close :: proc(ns: ^Net_Server) {
	for client in ns.clients {
		if client.active {
			net.close(client.socket)
		}
		if !client.joined && client.player != nil {
			shared.player_destroy(client.player)
		}
		free(client)
	}
	delete(ns.clients)
	net.close(ns.listener)
}
