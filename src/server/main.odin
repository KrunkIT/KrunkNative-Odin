package server_main

import "core:fmt"
import "core:time"

import shared "../shared"

Server_Config :: struct {
	tick_rate:   i32,
	listen_port: i32,
}

Server :: struct {
	config:      Server_Config,
	should_quit: bool,
	net_srv:     Net_Server,
	game:        shared.Game,
}

main :: proc() {
	fmt.println("==================================================")
	fmt.println("  KrunkNative Odin Dedicated Server v1.0.0 (60Hz)")
	fmt.println("==================================================")

	server := Server {
		config = Server_Config{
			tick_rate   = 60,
			listen_port = 21015,
		},
		should_quit = false,
	}

	config_path := shared.concat(shared.assets_path(), "config/game.toml")
	defer delete(config_path)
	gameplay_config := shared.config_load_gameplay(config_path)
	defer shared.config_destroy_gameplay(gameplay_config)

	net_srv, net_ok := net_server_init(int(server.config.listen_port))
	if net_ok {
		server.net_srv = net_srv
	}

	loaded_map, ok := shared.map_load_from_file("assets/maps/burg.json")
	if ok {
		fmt.printf("Server loaded map with %d spawn points and %d objects\n", len(loaded_map.spawns), len(loaded_map.objects))

		maps := []^shared.Map{loaded_map}
		shared.game_configure(&server.game, nil, maps, nil, gameplay_config.weapons, gameplay_config.classes)
		server.game.server = &server
		shared.game_init(&server.game, 0, 0, false)
	} else {
		fmt.eprintln("Failed to load the server map; quitting.")
		if net_ok {
			net_server_close(&server.net_srv)
		}
		return
	}

	target_frame_time := time.Second / time.Duration(server.config.tick_rate)
	fmt.printf("Server listening on 0.0.0.0:%d (Tick rate: %d Hz)\n", server.config.listen_port, server.config.tick_rate)

	last_time := time.now()
	now: f32

	// The process is a dedicated server, not a fixed-duration simulation.
	for !server.should_quit {
		tick_start := time.now()
		delta := f32(time.duration_seconds(time.diff(last_time, tick_start)))
		last_time = tick_start
		now += delta

		if net_ok {
			net_server_poll(&server.net_srv)
		}

		shared.game_tick(&server.game, now, delta)

		elapsed := time.diff(tick_start, time.now())
		if elapsed < target_frame_time {
			time.sleep(target_frame_time - elapsed)
		}

		free_all(context.temp_allocator)
	}

	if net_ok {
		net_server_close(&server.net_srv)
	}
	if loaded_map != nil {
		shared.map_destroy(loaded_map)
	}
}
