package krunker

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import curl "vendor:curl"

Network_HTTP_Capture :: struct {
	body: [dynamic]byte,
	headers: [dynamic]byte,
	body_limit_exceeded: bool,
}

network_http_write :: proc "c" (buffer: [^]byte, size, count: c.size_t, output: rawptr) -> c.size_t {
	context = runtime.default_context()
	total := int(size * count)
	if output == nil || total <= 0 do return 0
	capture := cast(^Network_HTTP_Capture)output
	if total > 4*1024*1024 - len(capture.body) { capture.body_limit_exceeded = true; return 0 }
	append(&capture.body, ..buffer[:total])
	return c.size_t(total)
}

network_http_header :: proc "c" (buffer: [^]byte, size, count: c.size_t, output: rawptr) -> c.size_t {
	context = runtime.default_context()
	total := int(size * count)
	if output == nil || total <= 0 do return 0
	capture := cast(^Network_HTTP_Capture)output
	if len(capture.headers) + total <= 65536 { append(&capture.headers, ..buffer[:total]) }
	return c.size_t(total)
}

// curl's TEXT events contain DNS, proxy and TLS details. Raw HEADER/DATA
// events are deliberately excluded because request URLs contain credentials.
network_http_debug :: proc "c" (handle: ^curl.CURL, kind: curl.infotype, data: [^]byte, size: c.size_t, user: rawptr) -> c.int {
	context = runtime.default_context()
	if kind == .TEXT { network_log("curl", strings.trim_space(string(data[:int(size)]))) }
	return 0
}

network_http_info :: proc(handle: ^curl.CURL, stage: string, code: curl.code, detail: string) -> i64 {
	status, verify, redirects: c.long
	lookup, connect, tls, first_byte, total: f64
	ip, effective: cstring
	curl.easy_getinfo(handle, .RESPONSE_CODE, &status)
	curl.easy_getinfo(handle, .SSL_VERIFYRESULT, &verify)
	curl.easy_getinfo(handle, .REDIRECT_COUNT, &redirects)
	curl.easy_getinfo(handle, .NAMELOOKUP_TIME, &lookup)
	curl.easy_getinfo(handle, .CONNECT_TIME, &connect)
	curl.easy_getinfo(handle, .APPCONNECT_TIME, &tls)
	curl.easy_getinfo(handle, .STARTTRANSFER_TIME, &first_byte)
	curl.easy_getinfo(handle, .TOTAL_TIME, &total)
	curl.easy_getinfo(handle, .PRIMARY_IP, &ip)
	curl.easy_getinfo(handle, .EFFECTIVE_URL, &effective)
	network_log(stage, fmt.tprintf("HTTP=%d curl=%v (%d: %s) detail=%s", status, code, int(code), string(curl.easy_strerror(code)), detail))
	network_log(stage, fmt.tprintf("peer=%s TLS_verify=%d redirects=%d effective_url=%s", string(ip), verify, redirects, string(effective)))
	network_log(stage, fmt.tprintf("timings_ms DNS=%.2f connect=%.2f TLS=%.2f first_byte=%.2f total=%.2f (cumulative)", lookup*1000, connect*1000, tls*1000, first_byte*1000, total*1000))
	return i64(status)
}

// Always preserves the response body, including non-2xx and transport errors.
// libcurl global initialization is owned by the caller.
network_http :: proc(url, method, body, stage: string) -> (result: [dynamic]byte, status: i64, ok: bool) {
	network_log(stage, fmt.tprintf("REQUEST %s %s connect_timeout=8000ms timeout=15000ms", method, url))
	network_log(stage, "request headers: Origin=https://krunker.io Referer=https://krunker.io/ User-Agent=Mozilla/5.0 (Krodin)")
	handle := curl.easy_init()
	if handle == nil { network_log(stage, "ERROR curl.easy_init returned nil"); return }
	defer curl.easy_cleanup(handle)
	url_c := strings.clone_to_cstring(url)
	body_c := strings.clone_to_cstring(body)
	defer delete(url_c)
	defer delete(body_c)
	capture: Network_HTTP_Capture
	defer delete(capture.headers)
	error_buffer: [curl.ERROR_SIZE]byte
	headers: ^curl.slist
	headers = curl.slist_append(headers, "Origin: https://krunker.io")
	headers = curl.slist_append(headers, "Referer: https://krunker.io/")
	headers = curl.slist_append(headers, "User-Agent: Mozilla/5.0 (Krodin)")
	defer curl.slist_free_all(headers)
	setup := []curl.code{
		curl.easy_setopt(handle, .URL, url_c),
		curl.easy_setopt(handle, .CONNECTTIMEOUT_MS, c.long(8000)),
		curl.easy_setopt(handle, .TIMEOUT_MS, c.long(15000)),
		curl.easy_setopt(handle, .ERRORBUFFER, rawptr(&error_buffer[0])),
		curl.easy_setopt(handle, .WRITEFUNCTION, curl.write_callback(network_http_write)),
		curl.easy_setopt(handle, .WRITEDATA, rawptr(&capture)),
		curl.easy_setopt(handle, .HEADERFUNCTION, curl.write_callback(network_http_header)),
		curl.easy_setopt(handle, .HEADERDATA, rawptr(&capture)),
		curl.easy_setopt(handle, .DEBUGFUNCTION, curl.debug_callback(network_http_debug)),
		curl.easy_setopt(handle, .VERBOSE, c.long(1)),
	}
	option_names := []string{"URL", "CONNECTTIMEOUT_MS", "TIMEOUT_MS", "ERRORBUFFER", "WRITEFUNCTION", "WRITEDATA", "HEADERFUNCTION", "HEADERDATA", "DEBUGFUNCTION", "VERBOSE"}
	for code, i in setup { if code != .E_OK { network_log(stage, fmt.tprintf("ERROR curl option=%s: %v %s", option_names[i], code, string(curl.easy_strerror(code)))); return } }
	if method == "POST" {
		headers = curl.slist_append(headers, "Content-Type: application/json")
		if curl.easy_setopt(handle, .POST, c.long(1)) != .E_OK || curl.easy_setopt(handle, .POSTFIELDS, rawptr(body_c)) != .E_OK { network_log(stage, "ERROR configuring POST"); return }
	}
	if code := curl.easy_setopt(handle, .HTTPHEADER, headers); code != .E_OK { network_log(stage, fmt.tprintf("ERROR setting headers: %v", code)); return }
	code := curl.easy_perform(handle)
	status = network_http_info(handle, stage, code, string(cast(cstring)&error_buffer[0]))
	network_log(stage, fmt.tprintf("response headers (%d bytes): %s", len(capture.headers), string(capture.headers[:])))
	network_log(stage, fmt.tprintf("response body bytes=%d limit_exceeded=%v", len(capture.body), capture.body_limit_exceeded))
	if status < 200 || status >= 300 || code != .E_OK { network_log(stage, fmt.tprintf("ERROR response body: %s", string(capture.body[:]))) }
	return capture.body, status, code == .E_OK
}
