package main

import "core:encoding/json"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	gameplay_packet :: proc(world: ^kproto.Krunker_World_State, args: ..kproto.Krunker_Msgpack_Value) -> bool {
		return kproto.krunker_world_apply_packet(world, args)
	}

	@(test)
	krunker_join_in_progress_has_authoritative_match_state :: proc(t: ^testing.T) {
		world: kproto.Krunker_World_State
		defer kproto.krunker_world_reset(&world)
		packet: [21]kproto.Krunker_Msgpack_Value
		for &value in packet { value = kproto.Krunker_Msgpack_Nil{} }
		packet[0], packet[1], packet[2] = "init", i64(2), i64(2)
		packet[4] = []kproto.Krunker_Msgpack_Value{[]kproto.Krunker_Msgpack_Value{i64(1), i64(2)}}
		packet[5] = []kproto.Krunker_Msgpack_Value{[]kproto.Krunker_Msgpack_Value{i64(1), i64(120)}, []kproto.Krunker_Msgpack_Value{i64(2), i64(90)}}
		packet[7] = []kproto.Krunker_Msgpack_Map_Entry{{key="gamRounds", value=i64(8)}}
		packet[12] = []kproto.Krunker_Msgpack_Map_Entry{
			{key="lck", value=true}, {key="lockT", value=i64(2500)}, {key="roundC", value=i64(5)},
			{key="obj", value=[]kproto.Krunker_Msgpack_Value{i64(3), i64(45000)}},
		}
		packet[20] = i64(162500)
		world.received_at = 100
		testing.expect(t, kproto.krunker_world_apply_packet(&world, packet[:]))
		testing.expect(t, world.match.team_scores == [3]u32{0,120,90} && world.match.round_wins[1] == 2)
		testing.expect(t, world.match.round_current == 3 && world.match.time_remaining == 162.5)
		testing.expect(t, world.move_lock && world.match.phase == .WARMUP && world.match.phase_remaining == 2.5)
		testing.expect(t, world.objective_uid == 3 && world.match.objective.rotation_remaining == 45)
		testing.expect(t, gameplay_packet(&world, "lkt", i64(0)) && world.match.phase == .LIVE)
		testing.expect(t, gameplay_packet(&world, "ts", i64(1), i64(130)) && world.match.team_scores[1] == 130)
		testing.expect(t, gameplay_packet(&world, "ts", kproto.Krunker_Msgpack_Nil{}) && world.match.team_scores == [3]u32{})
		testing.expect(t, gameplay_packet(&world, "t", "2:01", i64(0), i64(121100)) && world.match.time_remaining == 121.1)
		testing.expect(t, gameplay_packet(&world, "t", "1:02:03", i64(0)) && world.match.time_remaining == 3723)
		testing.expect(t, gameplay_packet(&world, "t", "4", i64(1)) && world.match.time_remaining == 3723,
			"end-screen countdown must not replace the match timer")
		packet[4], packet[5], packet[12], packet[20] = kproto.Krunker_Msgpack_Nil{}, kproto.Krunker_Msgpack_Nil{}, kproto.Krunker_Msgpack_Nil{}, kproto.Krunker_Msgpack_Nil{}
		kproto.krunker_world_apply_packet(&world, packet[:])
		testing.expect(t, !world.move_lock && world.match.team_scores == [3]u32{} && world.objective_uid == -1 && world.timer_text == "",
			"the next map must not inherit scores, locks, objective or timer text")
	}

	@(test)
	krunker_objective_uid_and_display_clocks :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		defer delete(map_inst.objects)
		wall := shared.Object{}
		point := shared.Object{objective=true, objective_id=4}
		append(&map_inst.objects, &wall, &point)
		append(&client.game.objective_indices, i32(1))
		world := &client.krunker_world
		world.has_match, world.received_at = true, 100
		world.match.phase = .LIVE
		gameplay_packet(world, "t", "2:00", i64(0), i64(120000))
		gameplay_packet(world, "ts", i64(1), i64(40))
		gameplay_packet(world, "obj", i64(4), i64(45000), true)
		gameplay_packet(world, "uobj", i64(4), i64(2))
		krunker_client_sync_match(&client, 101.25)
		testing.expect(t, client.game.match.objective.active_object_index == 1 && client.game.match.objective.active_zone == 4,
			"wire objective UID must resolve independently of its object index")
		testing.expect(t, client.game.match.time_remaining == 118.75 && client.game.match.objective.rotation_remaining == 43.75)
		testing.expect(t, client.game.match.team_scores[1] == 40 && world.match.time_remaining == 120 && world.match.objective.rotation_remaining == 45,
			"display clocks must never mutate authoritative timers or award local points")
		testing.expect(t, client.game.match.objective.owner_team == 0 && !client.game.match.objective.contested,
			"occupant count two does not identify Bravo or prove opposing teams are present")
		gameplay_packet(world, "obj", i64(8), i64(30000))
		krunker_client_sync_match(&client, 102)
		testing.expect(t, client.game.match.objective.active_object_index == -1,
			"an unknown point must hide the old highlight rather than display the wrong point")
	}

	@(test)
	krunker_score_kill_leaders_and_hit_confirmation :: proc(t: ^testing.T) {
		client: Client
		defer kproto.krunker_world_reset(&client.krunker_world)
		client.krunker.connected = true
		world := &client.krunker_world
		world.local_sid, world.mode_index, world.received_at = 7, 2, 10
		testing.expect(t, gameplay_packet(world, i64(5), i64(30), false, false))
		gameplay_packet(world, "5", i64(99), true, false)
		testing.expect(t, world.players[0].score == 30, "animation-only score cannot change total")
		gameplay_packet(world, "5", i64(12), false, true)
		gameplay_packet(world, "5", i64(-20), false, false)
		testing.expect(t, world.players[0].score == 0, "score must not underflow")
		medals := []kproto.Krunker_Msgpack_Value{i64(1), i64(100)}
		testing.expect(t, gameplay_packet(world, i64(6), medals, kproto.Krunker_Msgpack_Nil{}, i64(3), i64(1)))
		testing.expect(t, world.players[0].kills == 3, "kill count is the third argument, not the medal list")
		testing.expect(t, gameplay_packet(world, i64(7), []kproto.Krunker_Msgpack_Value{i64(7), i64(250), i64(90), i64(4)}))
		testing.expect(t, world.players[0].score == 250 && world.players[0].kills == 4,
			"Hardpoint leaderboard field two is objective points, not kills")
		world.mode_index = 0
		gameplay_packet(world, "7", []kproto.Krunker_Msgpack_Value{i64(7), i64(350), i64(5), i64(2)})
		testing.expect(t, world.players[0].deaths == 2)
		testing.expect(t, gameplay_packet(world, i64(4), i64(99), f64(25), false, true))
		color, visible := krunker_client_hit_color(&client, 10.2)
		testing.expect(t, visible && color.x == 1 && color.y == 0.25 && world.hit_lethal)
		_, expired := krunker_client_hit_color(&client, 10.4)
		testing.expect(t, !expired && world.players[0].health == 100, "hit UI must expire without applying damage locally")
	}

	@(test)
	krunker_control_flags_affect_prediction_and_reset_position_once :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		world := &client.krunker_world
		source := kproto.krunker_world_upsert_player(world, 7)
		source.socket_id = strings.clone("our-socket")
		for &packet in ([][2]kproto.Krunker_Msgpack_Value{{"noc",true},{"frz",true},{"unl",true},{"spb",f64(2)}}) {
			testing.expect(t, kproto.krunker_world_apply_packet(world, packet[:]))
		}
		krunker_client_apply_metadata(&client, client.me, source)
		testing.expect(t, client.me.noclip && client.me.frozen && client.me.unlimited_ammo && client.me.speed_boost == 2)
		client.me.velocity = {1,1,1}
		position, ammo := client.me.position, client.me.ammo[0]
		frame := shared.Input{delta=0.007, move_dir=0, shoot=true, jump=true}
		krunker_client_predict_input(&client, &frame)
		testing.expect(t, client.me.position == position && client.me.velocity == shared.Vec3{} && client.me.ammo[0] == ammo && client.me.shot_seq == 0,
			"freeze blocks both movement and firing while inputs still reach the server")
		client.me.frozen = false
		client.me.ammo[0] = 0
		krunker_client_predict_input(&client, &frame)
		testing.expect(t, client.me.position != position && client.me.ammo[0] == 0 && client.me.shot_seq == 1, "unlimited ammo must allow shots even with an empty magazine")
		gameplay_packet(world, "lm", i64(50), i64(20), i64(-30), f64(1.5))
		krunker_client_apply_motion(&client, client.me, source, false)
		testing.expect(t, client.me.position == shared.Vec3{50,20.01,-30} && client.me.direction.y == 1.5 && len(client.predicted_inputs) == 0 && len(client.krunker.input_commands) == 0,
			"move lock must snap to the server anchor and discard pre-lock prediction")
		client.me.position.x = 51
		krunker_client_apply_motion(&client, client.me, source, false)
		testing.expect(t, client.me.position.x == 51, "unrelated metadata must not reapply a reset")
		gameplay_packet(world, "ulm")
		testing.expect(t, !world.move_lock && source.frozen, "unfreeze and movement unlock are independent")
		testing.expect(t, !gameplay_packet(world, "chgp", "another-socket", i64(1), i64(2), i64(3)))
		testing.expect(t, gameplay_packet(world, "chgp", "our-socket", i64(1), i64(2), i64(3), true, true, i64(0)))
		krunker_client_apply_motion(&client, client.me, source, false)
		testing.expect(t, client.me.position == shared.Vec3{1,2,3} && abs(client.me.direction.y+math.PI/2) < 1e-5)
		gameplay_packet(world, "p", f64(0.4)); gameplay_packet(world, "mp", f64(0.7), true); gameplay_packet(world, "lv", i64(3))
		testing.expect(t, world.interact_progress == 0.4 && world.interact_manual_progress == 0.7 && world.interact_manual_visible && world.lives == 3)
	}

	@(test)
	krunker_death_round_end_and_team_change_are_authoritative :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		client.krunker.connected, client.in_game, client.has_life = true, true, true
		client.krunker.render_map_ready = true // Reuse fixture; no GL map load.
		world := &client.krunker_world
		world.ready, world.in_game, world.has_match = true, true, true
		world.match.phase, world.rounds_total = .LIVE, 8
		local := kproto.krunker_world_upsert_player(world, 7)
		local.active, local.has_position, local.class_index = true, true, 2
		gameplay_packet(world, "uid", "our-uid")
		gameplay_packet(world, "cda", "our-uid", []kproto.Krunker_Msgpack_Map_Entry{{key="t",value=i64(1)}})
		testing.expect(t, gameplay_packet(world, "tm", i64(7), i64(2)) && world.players[0].team == 2 && world.lobby_players[0].team == 2,
			"live team updates must replace the stale lobby assignment too")
		gameplay_packet(world, i64(3), i64(7), i64(4))
		snapshot: [18]kproto.Krunker_Msgpack_Value
		testing.expect(t, !gameplay_packet(world, "l", snapshot[:]) && !world.players[0].active && !world.in_game && world.players[0].deaths == 4,
			"a delayed movement snapshot cannot resurrect a dead player")
		krunker_client_sync_world(&client)
		testing.expect(t, !client.in_game && client.has_life && !client.me.active && !client.krunker.spawned)
		gameplay_packet(world, "start", "2:00", i64(2))
		testing.expect(t, world.players[0].active && !world.players[0].life_ended && world.in_game)
		gameplay_packet(world, "rds", i64(4), false, i64(2), []kproto.Krunker_Msgpack_Value{i64(0), i64(2), i64(1)})
		testing.expect(t, !world.in_game && world.match.round_current == 4 && world.match.round_wins == [3]u32{0,2,1})
		gameplay_packet(world, "end", i64(0), true, []kproto.Krunker_Msgpack_Map_Entry{{key="tms",value=[]kproto.Krunker_Msgpack_Value{[]kproto.Krunker_Msgpack_Value{i64(2),i64(200)}}}}, i64(2))
		testing.expect(t, world.match.phase == .ENDED && world.winner_team == 2 && world.end_result == 1 && world.match.team_scores[2] == 200)
		testing.expect(t, len(krunker_client_match_reason(&client)) > 0 && !gameplay_packet(world, "l", snapshot[:]))
	}

	@(test)
	krunker_gameplay_rejects_bad_packets_without_mutation :: proc(t: ^testing.T) {
		world := kproto.Krunker_World_State{local_sid=7,mode_index=2,objective_uid=3}
		defer kproto.krunker_world_reset(&world)
		for packet in ([][]kproto.Krunker_Msgpack_Value{
			{"ts",i64(99),i64(40)}, {"ts",i64(1),transmute(f64)u64(0x7ff0000000000000)}, {"lm",i64(1),i64(2)},
			{"lm",i64(1),transmute(f64)u64(0x7ff8000000000000),i64(2),i64(0)}, {"obj",i64(3),i64(-1)},
			{"uobj",i64(3),"bad"}, {"tm",i64(7),i64(99)}, {"spb",i64(-1)},
			{"7",[]kproto.Krunker_Msgpack_Value{i64(7),i64(40),i64(5)}}, {"gsc",i64(55)},
			{"end",i64(0)}, {"not-a-gameplay-opcode",true},
		}) {
			testing.expect(t, !kproto.krunker_world_apply_packet(&world, packet))
			testing.expect(t, world.objective_uid == 3 && world.match.team_scores == [3]u32{} && !world.move_lock)
		}
	}

	@(test)
	krunker_authored_objective_ids_survive_map_loading :: proc(t: ^testing.T) {
		path := "bin/objective-wire-ids-test.json"
		data := `{"name":"Wire IDs","spawns":[{"x":0,"y":0,"z":0}],"objects":[{"p":[0,0,0],"s":[10,10,10],"id":0},{"p":[0,0,0],"s":[10,10,10],"id":17,"objId":"5"},{"p":[0,0,0],"s":[10,10,10],"id":17}]}`
		// Use enum values to keep the fixture independent of prefab numbering.
		value, err := json.parse_string(data)
		if !testing.expect(t, err == .None) { return }
		defer json.destroy_value(value)
		root := value.(json.Object)
		objects := root["objects"].(json.Array)
		for i in 1..<3 { object := objects[i].(json.Object); object["id"] = json.Integer(shared.Prefab.OBJECTIVE) }
		encoded, encode_err := json.marshal(value)
		if !testing.expect(t, encode_err == nil) { return }
		defer delete(encoded)
		if !testing.expect(t, os.write_entire_file(path, encoded) == nil) { return }
		defer os.remove(path)
		map_inst, ok := shared.map_load_from_file(path)
		if !testing.expect(t, ok) { return }
		defer shared.map_destroy(map_inst)
		testing.expect(t, len(map_inst.objects) == 3 && map_inst.objects[1].objective_id == 4 && map_inst.objects[2].objective_id == 5)
	}
}
