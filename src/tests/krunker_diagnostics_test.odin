package main

import "core:fmt"
import "core:strings"
import krunker "../krunker"

test_krunker_diagnostics :: proc() -> bool {
	fixtures := []string{
		"https://example.invalid/seek-game?accessToken=FAKE-ACCESS&validationToken=FAKE-VALIDATION&game=FRA:test",
		"wss://example.invalid/ws?at=FAKE-ACCESS&clientKey=FAKE-CLIENT&gameId=FRA:test",
		`{"error":"expired", "nested":{"accessToken":"FAKE-ACCESS", "clientId":"FAKE-CLIENT", "validationToken":"FAKE-VALIDATION"}}`,
		"Authorization: Bearer FAKE-ACCESS\r\nSet-Cookie: session=FAKE-CLIENT; Secure; HttpOnly\r\nserver: test",
		`{"TOKEN":"FAKE-ACCESS", "cookie":"FAKE-CLIENT", "password":"FAKE-VALIDATION"}`,
		`{"token":"escaped\"FAKE-ACCESS", "game":"FRA:test"}`,
		"unlabelled JWT eyJhbGciOiJub25lIn0.eyJleHAiOjB9.signature",
	}
	for fixture in fixtures {
		safe := krunker.network_log_safe(fixture)
		secrets := []string{"FAKE-ACCESS", "FAKE-VALIDATION", "FAKE-CLIENT", "eyJhbGciOiJub25lIn0"}
		for secret in secrets {
			if strings.index(safe, secret) >= 0 { fmt.eprintln("Network redaction leaked a fixture credential"); delete(safe); return false }
		}
		delete(safe)
	}
	krunker.network_log_secret("fixture-secret-echo")
	safe := krunker.network_log_safe("server echoed fixture-secret-echo\n\x1b[31m failure")
	if strings.index(safe, "fixture-secret-echo") >= 0 || strings.index(safe, "\n") >= 0 || strings.index(safe, "\x1b") >= 0 { fmt.eprintln("Network free-text redaction/control escaping failed"); delete(safe); return false }
	delete(safe)
	safe = krunker.network_log_safe("error=fixture-secret-echo and more text", 8)
	if strings.index(safe, "fixture") >= 0 || strings.index(safe, "truncated") < 0 { fmt.eprintln("Network diagnostic truncation failed"); delete(safe); return false }
	delete(safe)
	safe = krunker.network_log_safe("game=FRA:test HTTP=403 error=invite expired")
	defer delete(safe)
	if safe != "game=FRA:test HTTP=403 error=invite expired" { fmt.eprintln("Network redaction removed useful diagnostics"); return false }
	fmt.println("Krunker network diagnostic redaction tests OK")
	return true
}
