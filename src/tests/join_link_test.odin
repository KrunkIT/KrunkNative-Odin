package main

import "core:fmt"
import shared "../shared"

test_join_link_parser :: proc() -> bool {
	invite, ok := shared.join_link_parse("https://krunker.io/?game=abc123&tm=1")
	if !ok || invite.scheme != "https" || invite.game_id != "abc123" || invite.team_hint != "1" || invite.host != "krunker.io" {
		fmt.eprintln("Invite link parsing failed")
		return false
	}
	shared.join_link_free(&invite)

	assigned, assigned_ok := shared.join_link_parse("wss://game.example:3443/ws?at=token&gameId=rank-7&clientKey=client")
	if !assigned_ok || assigned.scheme != "wss" || assigned.host != "game.example" || assigned.port != 3443 || assigned.game_id != "rank-7" || assigned.access_token != "token" || assigned.client_key != "client" {
		fmt.eprintln("Assigned game link parsing failed")
		return false
	}
	shared.join_link_free(&assigned)

	bare, bare_ok := shared.join_link_parse("abc123")
	if !bare_ok || bare.scheme != "game" || bare.game_id != "abc123" {
		fmt.eprintln("Bare game id parsing failed")
		return false
	}
	shared.join_link_free(&bare)

	_, ok = shared.join_link_parse("file:///tmp/lobby")
	if ok {
		fmt.eprintln("Unsupported scheme was accepted")
		return false
	}
	if shared.map_asset_name("sandstorm") != "sandstorm_v3" || shared.map_asset_name("ss_v3") != "sandstorm_v3" {
		fmt.eprintln("Sandstorm asset alias did not resolve to sandstorm_v3")
		return false
	}
	fmt.println("Join-link parser tests OK")
	return true
}
