package browser_access

import "core:encoding/base64"
import "core:encoding/json"
import "core:strings"

MAX_MESSAGE :: 65536
// Challenge proofs are short-lived, single-attempt values, never cached.
captcha_token_valid :: proc(token: string) -> bool {
	if len(token) == 0 || len(token) > 16384 { return false }
	for b in token { if b < 33 || b > 126 { return false } }
	return true
}
captcha_game_valid :: proc(game: string) -> bool {
	if len(game) == 0 || len(game) > 128 { return false }
	for b in game {
		if !(b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b >= '0' && b <= '9' || b == ':' || b == '-' || b == '_') { return false }
	}
	return true
}

// Match the official game's URL builder: production lobby hostnames use the
// secure WebSocket endpoint without exposing the matchmaker's internal port.
// The returned port remains diagnostic data and is only used by callers that
// explicitly support an IP-style assignment.
assignment_uses_explicit_port :: proc(host: string, port: i64) -> bool {
	return port != 443 && (strings.has_prefix(host, "ip_") || strings.has_prefix(host, "//ip_"))
}
Message :: struct {
	id: u64,
	kind: string,
	value: string,
}

Token_State :: enum { INVALID, EXPIRING, GUEST, READY }

payload_is_guest :: proc(value: json.Value) -> bool {
	// Inspect nested objects and arrays, including the FRVR extra.platform claim.
	pending: [dynamic]json.Value
	defer delete(pending)
	append(&pending, value)
	for len(pending) > 0 {
		item := pending[len(pending)-1]
		resize(&pending, len(pending)-1)
		if object, ok := item.(json.Object); ok {
			for key, child in object {
				if strings.equal_fold(key, "platform") {
					if text, valid := child.(json.String); valid {
						platform := strings.trim_space(string(text))
						if strings.equal_fold(platform, "anonymous") || strings.equal_fold(platform, "anon") { return true }
					}
				}
				append(&pending, child)
			}
		} else if array, ok := item.(json.Array); ok {
			for child in array { append(&pending, child) }
		}
	}
	return false
}

// Decode claims only to exclude guest access and schedule refresh. Server acceptance
// remains authoritative; this does not authenticate a JWT or verify its signature.
token_state :: proc(token: string, now: i64) -> Token_State {
	if len(token) == 0 || len(token) > 32768 { return .INVALID }
	parts := strings.split(token, ".")
	defer delete(parts)
	if len(parts) != 3 { return .INVALID }
	payload, err := base64.decode(parts[1], base64.DEC_URL_TABLE)
	if err != nil { return .INVALID }
	defer delete(payload)
	value, parse_err := json.parse(payload, parse_integers = true)
	if parse_err != .None { return .INVALID }
	defer json.destroy_value(value)
	object, ok := value.(json.Object)
	if !ok { return .INVALID }
	if payload_is_guest(value) { return .GUEST }
	exp, valid := object["exp"].(json.Integer)
	if !valid { return .INVALID }
	if i64(exp) <= 60 || now >= i64(exp)-60 { return .EXPIRING }
	return .READY
}

usable :: proc(token: string, now: i64) -> bool { return token_state(token, now) == .READY }

// Deliberately narrow: permission, capacity, and generic 403 failures must not refresh.
token_rejection_reason :: proc(reason: string) -> bool {
	for code in ([]string{"TOKEN_EXPIRED", "INVALID_TOKEN", "ACCESS_TOKEN_EXPIRED", "INVALID_ACCESS_TOKEN", "Token expired", "Access token expired", "Invalid access token", "jwt expired", "invalid token"}) {
		if strings.equal_fold(strings.trim_space(reason), code) { return true }
	}
	return false
}

captcha_required :: proc(body: []byte) -> bool {
	value, err := json.parse(body)
	if err != .None { return false }
	defer json.destroy_value(value)
	object, ok := value.(json.Object)
	if !ok { return false }
	for key in ([]string{"code", "error", "message"}) {
		if text, valid := object[key].(json.String); valid {
			code := strings.trim_space(string(text))
			if strings.equal_fold(code, "CaptchaRequired") || strings.equal_fold(code, "CAPTCHA_REQUIRED") { return true }
		}
	}
	return false
}

token_rejected :: proc(status: i64, body: []byte) -> bool {
	if status < 200 || status >= 500 { return false }
	if captcha_required(body) { return false }
	if token_rejection_reason(string(body)) { return true }
	value, err := json.parse(body)
	if err != .None { return false }
	defer json.destroy_value(value)
	object, ok := value.(json.Object)
	if !ok { return false }
	for key in ([]string{"code", "error", "message"}) {
		if text, valid := object[key].(json.String); valid {
			if token_rejection_reason(string(text)) { return true }
		}
	}
	return false
}

official_source :: proc(source: string) -> bool {
	return source == "https://krunker.io" || strings.has_prefix(source, "https://krunker.io/")
}

// Browser-controlled values never reach diagnostics verbatim, including unknown codes.
diagnostic_text :: proc(code: string) -> string {
	switch code {
	case "HELPER_STARTED": return "Browser helper connected over private pipes."
	case "LOADER_READY": return "Official WebView2 loader loaded."
	case "RUNTIME_READY": return "Installed WebView2 runtime detected."
	case "PROFILE_NEW": return "No remembered account session; browser will be visible."
	case "PROFILE_REMEMBERED": return "Remembered browser profile found."
	case "ENVIRONMENT_READY": return "WebView2 environment ready; creating browser controller."
	case "CONTROLLER_READY": return "WebView2 controller ready; loading https://krunker.io/."
	case "NAVIGATING_OFFICIAL": return "Top-level navigation to the official site; waiting for page initialization."
	case "NAVIGATING_LOGIN": return "Top-level navigation outside the official origin; token capture paused."
	case "WAIT_LOGIN": return "Waiting for nonempty krunker_username; access token has not been read."
	case "WAIT_STORAGE": return "Waiting one second for the site to finish writing account access to localStorage; token reads paused."
	case "GUEST_TOKEN": return "Guest JWT detected (platform is anonymous or anon); waiting for an account token. Payload omitted."
	case "WAIT_SDK": return "Waiting for official FRVR SDK; username exists but no usable stored access token is available."
	case "PENDING": return "Username exists; stored access is missing, malformed, or expiring. Requesting official SDK renewal."
	case "WAIT_TOKEN": return "SDK renewal completed; waiting for a usable localStorage access token under the username gate."
	case "READY": return "Username gate passed; localStorage JWT has usable expiry and no guest platform claim. Token contents omitted."
	case "SESSION_REJECTED": return "Official SDK rejected renewal; browser shown for interactive login."
	case "OTHER_ORIGIN": return "Page origin or frame check failed; token capture skipped."
	case "SDK_AVAILABLE": return "Official FRVR authentication SDK detected."
	case "STORAGE_UNAVAILABLE": return "Official page localStorage could not be read."
	case "SCRIPT_FAILED": return "Browser authentication script failed; waiting for the page to initialize."
	case "SCRIPT_INVALID_RESULT": return "Browser authentication script returned no recognized state; waiting for page initialization."
	case "CAPTCHA_ARMED": return "Socket handoff v2 installed before site scripts; assigned browser sockets will be captured before opening."
	case "WAIT_CAPTCHA": return "Waiting for the official page to request and complete its challenge."
	case "CAPTCHA_READY": return "Challenge proof captured before browser matchmaking could consume it; handing it to the native client."
	case "WAIT_SOCKET_INTENT": return "Browser assignment received; waiting for the official page to select its token and build the socket URL."
	case "CAPTCHA_ASSIGNMENT": return "Exact browser socket URL captured before connection; handing it to the native client."
	case "CAPTCHA_NO_CHALLENGE": return "The browser opened a game socket before requesting a challenge proof; continuing to wait for the proof."
	case: return "Unrecognized browser diagnostic (details omitted)."
	}
}

// Only fixed, native-owned text reaches the UI. SDK errors and pipe contents may contain secrets.
status_text :: proc(code: string) -> string {
	switch code {
	case "VISIBLE": return "Log in through the Krunker browser window to join. Close it or press Cancel to stop."
	case "SDK_AVAILABLE": return "Official FRVR authentication SDK detected."
	case "SDK_UNAVAILABLE": return "Krunker did not expose FRVR.auth.getFreshAccessToken() in WebView2. Wait for the site to load, then retry Login."
	case "SESSION_REJECTED": return "Krunker rejected this browser session. Sign in in the browser, or use Forget browser session and try again."
	case "RUNTIME_MISSING": return "Install Microsoft Edge WebView2 Evergreen Runtime from https://developer.microsoft.com/microsoft-edge/webview2/ and retry Join."
	case "LOADER_MISSING": return "WebView2Loader.dll is missing. Rebuild or reinstall the Windows package."
	case "CANCELLED": return "Browser access cancelled. Press Join to try again."
	case "TIMEOUT": return "Browser access timed out. Check your connection and retry Join."
	case "PROFILE_FAILED": return "Cannot open the Krodin browser profile under LOCALAPPDATA. Check its permissions and close other Krodin browsers."
	case "STORAGE_UNAVAILABLE": return "Krunker browser storage is unavailable. Allow site storage or use Forget browser session and try Login again."
	case "GUEST_TOKEN": return "Guest access detected. Complete account login in the Krunker browser window before joining."
	case "BAD_TOKEN": return "The browser returned an access token without a usable expiry. Complete account login in the browser, then retry Join."
	case "CAPTCHA_VISIBLE": return "Complete any verification in the Krunker window. The native client will continue automatically. Close it or press Cancel to stop."
	case "CAPTCHA_ASSIGNMENT": return "Browser match found; opening the native game connection."
	case "CAPTCHA_BAD_TOKEN": return "The browser returned an invalid challenge proof. Retry Join."
	case "CAPTCHA_LOGIN_REQUIRED": return "The verification browser has no logged-in username. Click Login, complete account login, then retry Join."
	case "CAPTCHA_SOCKET_MISMATCH": return "The browser socket did not match its lobby assignment. Retry Join and check the network log."
	case "CAPTCHA_NO_CHALLENGE": return "The browser did not request a challenge proof. Native handoff could not proceed; retry Join or inspect the network log."
	case "CAPTCHA_REJECTED": return "Krunker still requires verification after the native challenge retry. Handoff failed; see logs/krunker-network.log."
	case "CAPTCHA_SETUP_FAILED": return "Could not install the browser challenge handoff. Rebuild the browser helper and retry Join."
	case: return "Browser access failed. Retry Join, or rebuild the Windows browser helper."
	}
}
