package main

import "core:fmt"
import "core:os"
import curl "vendor:curl"
import krunker "../../src/krunker"

// Offline integration probe. Run via tools/test_network_diagnostics.py.
main :: proc() {
	if len(os.args) != 2 { fmt.eprintln("usage: network_diagnostics_test <local-mock-base-url>"); os.exit(2) }
	if curl.global_init(curl.GLOBAL_DEFAULT) != .E_OK { os.exit(2) }
	defer curl.global_cleanup()
	krunker.network_log_begin()
	krunker.network_log_secret("registered-secret-echo")
	base := os.args[1]
	if !test_local_websocket(base) { os.exit(1) }
	// Reproduce the original on-wire error, then verify the actual client's
	// serializer/encoder produces a dataQuery the server can parse.
	malformed := krunker.network_url_encode(`%!(MISSING CLOSE BRACE)v":"fixture-version"}`)
	defer delete(malformed)
	bad_body, bad_status, bad_ok := krunker.network_http(fmt.tprintf("%s/seek-game?dataQuery=%s", base, malformed), "GET", "", "mock-seek-malformed")
	if !bad_ok || bad_status != 500 { fmt.eprintln("malformed query did not reproduce server rejection"); os.exit(1) }
	delete(bad_body)
	query, query_ok := krunker.krunker_seek_data_query("fixtureOpaqueVersion0123456789abcd")
	if !query_ok { fmt.eprintln("seek-game dataQuery serialization failed"); os.exit(1) }
	defer delete(query)
	encoded_query := krunker.network_url_encode(query)
	defer delete(encoded_query)
	seek_body, seek_status, seek_ok := krunker.network_http(fmt.tprintf("%s/seek-game?dataQuery=%s", base, encoded_query), "GET", "", "mock-seek-valid")
	if !seek_ok || seek_status != 200 || string(seek_body[:]) != "seek verified" { fmt.eprintln("serialized seek-game query rejected by mock server"); os.exit(1) }
	delete(seek_body)
	body, status, ok := krunker.network_http(fmt.tprintf("%s/reject?accessToken=FAKE-QUERY-SECRET&game=FRA:test", base), "GET", "", "mock-reject")
	if !ok || status != 403 || len(body) == 0 { fmt.eprintln("403 response body/status lost"); os.exit(1) }
	delete(body)
	body, status, ok = krunker.network_http(fmt.tprintf("%s/post", base), "POST", `{"test":"POST body remains alive through perform"}`, "mock-post")
	if !ok || status != 200 || string(body[:]) != "POST verified" { fmt.eprintln("POST body lifetime regression"); os.exit(1) }
	delete(body)
	body, status, ok = krunker.network_http(fmt.tprintf("%s/success", base), "GET", "", "mock-success")
	if !ok || status != 200 || string(body[:]) != "SECRET-SUCCESS-BODY" { fmt.eprintln("success body not preserved"); os.exit(1) }
	delete(body)
	body, status, ok = krunker.network_http(fmt.tprintf("%s/drop", base), "GET", "", "mock-drop")
	if ok || status != 0 { fmt.eprintln("transport failure not reported"); os.exit(1) }
	delete(body)
	fmt.println("Offline network diagnostic integration tests OK")
}
