package browser_access

import "core:encoding/base64"
import "core:fmt"
import "core:strings"
import "core:testing"

when ODIN_TEST {
	fixture_token :: proc(payload: string) -> string {
		encoded := base64.encode(transmute([]byte)payload, base64.ENC_URL_TABLE, options = {.No_Padding})
		defer delete(encoded)
		return fmt.aprintf("eyJhbGciOiJub25lIn0.%s.fixture", string(encoded))
	}
	@(test)
	expiry_refresh_boundary :: proc(t: ^testing.T) {
		token := fixture_token(`{"exp":1061}`); defer delete(token)
		testing.expect(t, usable(token, 1000))
		testing.expect(t, !usable(token, 1001), "refresh starts exactly 60 seconds before expiry")
		testing.expect(t, !usable(token, 1061))
		for payload in ([]string{`{}`, `{"exp":"2000"}`, `{"exp":2000.5}`, `{"exp":null}`, `{"exp":-1}`, `{"exp":0}`, `[]`, `not json`}) {
			bad := fixture_token(payload)
			testing.expect(t, !usable(bad, 1000), "unknown or malformed expiry cannot be reused")
			delete(bad)
		}
		for bad in ([]string{"", "opaque", "x.%%%.x", "a.b.c.d"}) { testing.expect(t, !usable(bad, 1000)) }
	}
	@(test)
	guest_platform_claims_are_never_usable :: proc(t: ^testing.T) {
		for payload in ([]string{
			`{"exp":4102444800,"extra":{"identifier":"fixture-id","platform":"anonymous","verified":true},"iss":"FRVR","sub":"fixture-subject"}`,
			`{"exp":4102444800,"platform":"anon"}`,
			`{"exp":4102444800,"extra":{"nested":[{"platform":" ANONYMOUS "}]}}`,
			`{"exp":4102444800,"extra":{"platform":"username"},"other":{"Platform":"Anon"}}`,
			`{"exp":1,"extra":{"platform":"anonymous"}}`,
		}) {
			token := fixture_token(payload)
			testing.expect(t, token_state(token, 1000) == .GUEST)
			testing.expect(t, !usable(token, 1000), "verified or unexpired guest access must never be selected")
			delete(token)
		}
		for payload in ([]string{
			`{"exp":4102444800,"extra":{"platform":"username","verified":true}}`,
			`{"exp":4102444800,"extra":{"platform":"anonymously"}}`,
			`{"exp":4102444800,"extra":{"description":"anonymous","platform":null}}`,
			`{"exp":4102444800}`,
		}) {
			token := fixture_token(payload)
			testing.expect(t, token_state(token, 1000) == .READY, "only explicit guest platform values exclude otherwise usable access")
			delete(token)
		}
	}
	@(test)
	only_explicit_token_rejections_refresh :: proc(t: ^testing.T) {
		testing.expect(t, token_rejected(401, transmute([]byte)string(`{"error":"jwt expired"}`)))
		testing.expect(t, token_rejected(403, transmute([]byte)string(`{"code":"INVALID_ACCESS_TOKEN"}`)))
		testing.expect(t, token_rejected(200, transmute([]byte)string(`{"error":"TOKEN_EXPIRED"}`)))
		testing.expect(t, token_rejected(401, transmute([]byte)string("Invalid token")))
		for body in ([]string{`Forbidden`, `{"error":"Forbidden"}`, `{"error":"Lobby full"}`, `{"message":"Expired lobby"}`, `{"description":"invalid token"}`, `{"error":{"message":"jwt expired"}}`}) {
			testing.expect(t, !token_rejected(403, transmute([]byte)body))
		}
		testing.expect(t, !token_rejected(500, transmute([]byte)string(`{"error":"jwt expired"}`)))
	}
	@(test)
	captcha_is_distinct_from_token_rejection :: proc(t: ^testing.T) {
		for body in ([]string{`{"error":"CaptchaRequired"}`, `{"code":"CAPTCHA_REQUIRED"}`, `{"message":" captchaRequired "}`, `{"error":"CaptchaRequired","message":"Invalid token"}`}) {
			testing.expect(t, captcha_required(transmute([]byte)body))
			for status in ([]i64{200, 400, 401, 403, 429}) {
				testing.expect(t, !token_rejected(status, transmute([]byte)body), "CAPTCHA must never invalidate access or trigger authentication retry")
			}
		}
		for body in ([]string{`{"error":"Invalid token"}`, `{"error":"Forbidden"}`, `{"description":"CaptchaRequired"}`, `{"error":"CaptchaRequired yesterday"}`, `not json`}) {
			testing.expect(t, !captcha_required(transmute([]byte)body))
		}
	}
	@(test)
	official_top_level_source_and_redacted_status :: proc(t: ^testing.T) {
		for source in ([]string{"https://krunker.io/", "https://krunker.io/?game=FRA:fixture"}) { testing.expect(t, official_source(source)) }
		for source in ([]string{"http://krunker.io/", "https://krunker.io.evil.invalid/", "https://krunker.io@evil.invalid/", "https://krunker.io:444/", "https://gapi.svc.krunker.io/"}) { testing.expect(t, !official_source(source)) }
		safe := status_text("eyJsecret.refresh_token=password")
		testing.expect(t, !strings.contains(safe, "eyJsecret") && !strings.contains(safe, "password"))
		for code in ([]string{"eyJsecret.refresh_token=password", "READY eyJsecret", "WAIT_LOGIN password", "", "READY", "WAIT_LOGIN", "PENDING", "GUEST_TOKEN"}) {
			text := diagnostic_text(code)
			testing.expect(t, !strings.contains(text, "eyJsecret") && !strings.contains(text, "password"), "diagnostics must use only fixed allowlisted text")
		}
	}
}
