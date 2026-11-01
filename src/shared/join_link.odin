package shared

import "core:strconv"
import "core:strings"
import "core:fmt"

// Join_Link is the normalized form of an invite copied from Krunker's lobby
// UI.  Krunker invite links use /?game=<id>; assigned game links use the
// WebSocket form described in the reverse engineering reports.  Keeping both
// forms here lets the client choose the appropriate transport later without
// making the menu know about URL syntax.
Join_Link :: struct {
	raw:          string,
	scheme:       string,
	host:         string,
	port:         i32,
	path:         string,
	game_id:      string,
	team_hint:    string,
	access_token: string,
	client_key:   string,
	client_uid:   string,
	bypass_token: string,
	tc:           string,
	dm:           string,
}

join_link_free :: proc(link: ^Join_Link) {
	if link == nil do return
	delete(link.raw)
	delete(link.scheme)
	delete(link.host)
	delete(link.path)
	delete(link.game_id)
	delete(link.team_hint)
	delete(link.access_token)
	delete(link.client_key)
	delete(link.client_uid)
	delete(link.bypass_token)
	delete(link.tc)
	delete(link.dm)
	link^ = {}
}

join_link_clone :: proc(value: string) -> string {
	if len(value) == 0 do return ""
	return strings.clone(value)
}

join_link_query_value :: proc(query, key: string) -> string {
	for field in strings.split(query, "&") {
		eq := strings.index(field, "=")
		if eq < 0 do continue
		if field[:eq] == key {
			return join_link_clone(field[eq + 1:])
		}
	}
	return ""
}

join_link_parse :: proc(input: string) -> (link: Join_Link, ok: bool) {
	value := strings.trim_space(input)
	if len(value) == 0 do return

	// Browser invite links are copied as https://krunker.io/?game=... .
	// Accept the bare game id as a convenience for clipboard workflows.
	if strings.index(value, "://") < 0 {
		if strings.index(value, "=") < 0 && strings.index(value, "/") < 0 {
			link.game_id = join_link_clone(value)
			link.raw = join_link_clone(value)
			link.scheme = join_link_clone("game")
			return link, len(link.game_id) > 0
		}
		value = fmt.tprintf("https://%s", value)
	}

	separator := strings.index(value, "://")
	if separator <= 0 do return
	link.scheme = join_link_clone(strings.to_lower(value[:separator]))
	if link.scheme != "http" && link.scheme != "https" && link.scheme != "ws" && link.scheme != "wss" && link.scheme != "krunker" && link.scheme != "tcp" {
		join_link_free(&link)
		return
	}

	rest := value[separator + 3:]
	authority_end := len(rest)
	if i := strings.index(rest, "/"); i >= 0 && i < authority_end { authority_end = i }
	if i := strings.index(rest, "?"); i >= 0 && i < authority_end { authority_end = i }
	authority := rest[:authority_end]
	if len(authority) == 0 {
		join_link_free(&link)
		return
	}

	// Invite URLs have a normal host. Direct game URLs may include a port.
	port: i32 = 0
	host := authority
	if colon := strings.last_index(authority, ":"); colon > 0 && colon + 1 < len(authority) {
		if parsed, parsed_ok := strconv.parse_i64(authority[colon + 1:]); parsed_ok && parsed > 0 && parsed <= 65535 {
			host = authority[:colon]
			port = i32(parsed)
		}
	}
	if len(host) == 0 {
		join_link_free(&link)
		return
	}
	link.host = join_link_clone(host)
	link.port = port

	path_start := authority_end
	query_start := strings.index(rest, "?")
	if path_start < len(rest) {
		path_end := query_start
		if path_end < 0 { path_end = len(rest) }
		if path_end > path_start { link.path = join_link_clone(rest[path_start:path_end]) }
	}
	if query_start >= 0 && query_start + 1 < len(rest) {
		query := rest[query_start + 1:]
		link.game_id = join_link_query_value(query, "game")
		// Assigned game URLs use gameId while browser invite URLs use game.
		// Normalize both forms for callers that only need the match identity.
		if len(link.game_id) == 0 {
			link.game_id = join_link_query_value(query, "gameId")
		}
		link.team_hint = join_link_query_value(query, "tm")
		link.access_token = join_link_query_value(query, "at")
		link.client_key = join_link_query_value(query, "clientKey")
		link.client_uid = join_link_query_value(query, "clientUID")
		link.bypass_token = join_link_query_value(query, "bpt")
		link.tc = join_link_query_value(query, "tc")
		link.dm = join_link_query_value(query, "dm")
	}
	link.raw = join_link_clone(value)
	return link, true
}

join_link_display :: proc(link: ^Join_Link) -> string {
	if link == nil do return ""
	if len(link.game_id) > 0 {
		return fmt.tprintf("Game %s", link.game_id)
	}
	if len(link.host) > 0 {
		if link.port > 0 { return fmt.tprintf("%s:%d", link.host, link.port) }
		return strings.clone(link.host)
	}
	return ""
}
