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
	fmt.println("  KrunkNative Odin Dedicated Server v1.0.0")
	fmt.println("==================================================")

	server := Server {
		config = Server_Config{
			tick_rate   = 64,
			listen_port = 21015,
		},
		should_quit = false,
	}

	config_path := shared.concat(shared.assets_path(), "config/game.toml")
	defer delete(config_path)
	gameplay_config := shared.config_load_gameplay(config_path)
	defer shared.config_destroy_gameplay(gameplay_config)
	if gameplay_config.game.tick_rate >= 30 && gameplay_config.game.tick_rate <= 240 {
		server.config.tick_rate = gameplay_config.game.tick_rate
	}

	net_srv, net_ok := net_server_init(int(server.config.listen_port))
	if net_ok {
		server.net_srv = net_srv
	}

	shared.load_default_maps()
	shared.game_configure(&server.game, &gameplay_config.game, nil, nil, gameplay_config.weapons, gameplay_config.classes)
	shared.game_init(&server.game, -1, 0, false)
	if server.game.ready {
		fmt.printf("Server loaded rotation map with %d spawn points, %d objects, and %d objectives\n", len(server.game.map_inst.spawns), len(server.game.map_inst.objects), len(server.game.objective_indices))

		server.game.server = &server
	} else {
		fmt.eprintln("Failed to load the server map; quitting.")
		if net_ok {
			net_server_close(&server.net_srv)
		}
		return
	}

	target_frame_time := time.Second / time.Duration(server.config.tick_rate)
	fixed_delta := 1.0 / f32(server.config.tick_rate)
	fmt.printf("Server listening on 0.0.0.0:%d (Tick rate: %d Hz)\n", server.config.listen_port, server.config.tick_rate)

	// A fixed sleep-per-frame loop does NOT run in real time on Windows:
	// time.sleep() has ~15.6 ms granularity, so sleeping the ~7.8 ms left to
	// a 128 Hz boundary actually stalls ~15.6 ms and the whole simulation
	// (timer, movement) runs at about half real-time. Accumulate wall clock
	// time instead and run whatever number of fixed sub-steps that elapses;
	// the sim then advances at the configured tick rate no matter how coarse
	// the sleep is.
	//
	// The default 64 Hz matches the 15.6 ms Windows timer quantum exactly, and
	// raising the timer resolution to ~1 ms tightens the sleep so the fixed
	// clock lands on time instead of jittering between 15.6 and 31.2 ms.
	server_set_timer_precision()
	defer server_restore_timer_precision()

	now: f32
	broadcast_tick: u32

	accumulator: time.Duration
	last_wall := time.now()

	for !server.should_quit {
		wall_frame := time.diff(last_wall, time.now())
		last_wall = time.now()

		// Clamp a hung frame so the sim never tries to spiral back to catch
		// up after a long stall (e.g. terminal pause or debugger breakpoint).
		if wall_frame > 250 * time.Millisecond {
			wall_frame = 250 * time.Millisecond
		}
		accumulator += wall_frame

		for accumulator >= target_frame_time {
			accumulator -= target_frame_time
			now += fixed_delta

			if net_ok {
				net_server_poll(&server.net_srv, &server.game)
				net_server_queue_inputs(&server.net_srv, fixed_delta)
			}

			shared.game_tick(&server.game, now, fixed_delta)
			if net_ok {
				broadcast_tick += 1
				// The simulation runs at the full 64 Hz; snapshots do not need
				// to. Keeping them at 32 Hz (every other tick) leaves TCP
				// headroom for input and avoids starving slower clients.
				if broadcast_tick % 2 == 0 {
					net_server_broadcast_match(&server.net_srv, &server.game)
				}
			}
		}

		// Sleep the fraction left in the current sub-step, then re-enter the
		// accumulator above. Windows sleeps round UP to the timer resolution,
		// so leave a 1 ms margin and spin out the tail; this keeps the loop
		// cadence at exactly one tick per frame instead of drifting late.
		remaining := target_frame_time - time.diff(last_wall, time.now())
		if remaining > 0 {
			when ODIN_OS == .Windows {
				if remaining > 2 * time.Millisecond {
					time.sleep(remaining - time.Millisecond)
				}
				for time.diff(last_wall, time.now()) < target_frame_time {
				}
			} else {
				time.sleep(remaining)
			}
		}

		free_all(context.temp_allocator)
	}

	if net_ok {
		net_server_close(&server.net_srv)
	}
	shared.game_destroy(&server.game)
	shared.unload_default_maps()
}
