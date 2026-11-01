package krunker

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

NETWORK_LOG_PATH :: "logs/krunker-network.log"
network_log_attempt: u64
network_log_started: time.Time
network_log_secrets: [dynamic]string
network_log_file_warning: bool

network_log_secret :: proc(secret: string) {
	if len(secret) == 0 do return
	for existing in network_log_secrets { if existing == secret do return }
	append(&network_log_secrets, strings.clone(secret))
}

network_log_sensitive_key :: proc(key: string) -> bool {
	keys := []string{"accessToken", "validationToken", "clientKey", "clientId", "clientUID", "at", "bpt", "token", "authorization", "cookie", "set-cookie", "password", "access_token", "refresh_token"}
	for candidate in keys {
		if strings.equal_fold(key, candidate) do return true
	}
	return false
}

network_log_word :: proc(b: byte) -> bool {
	return b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b >= '0' && b <= '9' || b == '_' || b == '-'
}

// Redact BEFORE truncating, including secrets echoed outside a JSON/query field.
// The returned string is owned by the caller.
network_log_safe :: proc(input: string, limit: int = 16384) -> string {
	value := strings.clone(input)
	defer delete(value)
	for secret in network_log_secrets {
		replaced, allocated := strings.replace_all(value, secret, "[REDACTED]")
		if allocated { delete(value); value = replaced }
	}
	out: [dynamic]byte
	defer delete(out)
	i := 0
	for i < len(value) {
		start := i
		if network_log_word(value[i]) {
			for i < len(value) && network_log_word(value[i]) { i += 1 }
			key := value[start:i]
			j := i
			if j < len(value) && (value[j] == '"' || value[j] == '\'') { j += 1 }
			for j < len(value) && (value[j] == ' ' || value[j] == '\t') { j += 1 }
			if network_log_sensitive_key(key) && j < len(value) && (value[j] == ':' || value[j] == '=') {
				j += 1
				for j < len(value) && (value[j] == ' ' || value[j] == '\t') { j += 1 }
				quote: byte
				if j < len(value) && (value[j] == '"' || value[j] == '\'') { quote = value[j]; j += 1 }
				append(&out, value[start:j])
				append(&out, "[REDACTED]")
				line_value := strings.equal_fold(key, "authorization") || strings.equal_fold(key, "cookie") || strings.equal_fold(key, "set-cookie")
				for j < len(value) {
					b := value[j]
					if quote != 0 {
						if b == '\\' && j+1 < len(value) { j += 2; continue }
						if b == quote do break
					} else {
						if b == '\r' || b == '\n' do break
						if !line_value && (b == '&' || b == '#' || b == ' ' || b == '\t' || b == ',' || b == '}' || b == ']' || b == '"' || b == '\'') do break
					}
					j += 1
				}
				i = j
				continue
			}
			// JWTs can appear in free text without a field name.
			if strings.has_prefix(key, "eyJ") && len(key) > 12 {
				for i < len(value) && (network_log_word(value[i]) || value[i] == '.' || value[i] == '=') { i += 1 }
				append(&out, "[REDACTED JWT]")
			} else { append(&out, key) }
			continue
		}
		if value[i] < 32 || value[i] == 127 { append(&out, ' ') } else { append(&out, value[i]) }
		i += 1
	}
	if len(out) > limit { return fmt.aprintf("%s ... [truncated; sanitized bytes=%d]", string(out[:limit]), len(out)) }
	return strings.clone(string(out[:]))
}

network_log :: proc(stage, message: string) {
	safe := network_log_safe(message)
	defer delete(safe)
	stamp, _ := time.time_to_rfc3339(time.now(), include_nanos = false, allocator = context.temp_allocator)
	elapsed := network_log_attempt == 0 ? 0.0 : time.duration_milliseconds(time.since(network_log_started))
	line := fmt.tprintf("[Krunker][%s][attempt=%d +%.1fms][%s] %s\n", stamp, network_log_attempt, elapsed, stage, safe)
	fmt.print(line)
	os.make_directory_all("logs")
	file, err := os.open(NETWORK_LOG_PATH, {.Write, .Append, .Create})
	if err == nil {
		defer os.close(file)
		_, write_err := os.write_string(file, line)
		if write_err == nil do return
	}
	if !network_log_file_warning { fmt.eprintln("[Krunker] Could not write logs/krunker-network.log; diagnostics continue on console."); network_log_file_warning = true }
}

network_log_begin :: proc() {
	for secret in network_log_secrets { delete(secret) }
	clear(&network_log_secrets)
	network_log_attempt += 1
	network_log_started = time.now()
	cwd, _ := os.get_working_directory(context.temp_allocator)
	network_log("join", fmt.tprintf("BEGIN cwd=%s log=%s/%s", cwd, cwd, NETWORK_LOG_PATH))
}
