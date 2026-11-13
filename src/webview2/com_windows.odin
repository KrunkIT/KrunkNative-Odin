package webview2

import "base:runtime"
import win "core:sys/windows"

// Minimal shared ABI from Microsoft.Web.WebView2 1.0.3650.58, WebView2.h.
COM :: struct { v: ^[64]rawptr }
Handler :: struct { v: ^[4]rawptr, iid: win.GUID }

query :: proc "system" (this: ^Handler, iid: ^win.GUID, out: ^rawptr) -> win.HRESULT {
	context = runtime.default_context()
	if out == nil { return win.HRESULT(-2147467261) }
	out^ = nil
	if iid^ == this.iid || iid^ == win.IUnknown_UUID^ { out^ = this; return 0 }
	return win.HRESULT(-2147467262)
}
// Handlers are static and must live until their browser environment closes.
retain :: proc "system" (this: rawptr) -> u32 { return 2 }
release :: proc "system" (this: rawptr) -> u32 { return 1 }
init_handler :: proc(h: ^Handler, v: ^[4]rawptr, iid: ^u16, invoke: rawptr) {
	v^ = {rawptr(query), rawptr(retain), rawptr(release), invoke}
	h.v = v
	win.IIDFromString(cast(cstring16)iid, &h.iid)
}
add_ref :: proc(object: ^COM) { (cast(proc "system" (^COM) -> u32)object.v[1])(object) }
release_com :: proc(object: ^COM) { if object != nil { (cast(proc "system" (^COM) -> u32)object.v[2])(object) } }

// Returned text uses the temporary allocator. Never retain it across event-loop iterations.
get_text :: proc(object: ^COM, slot: int, limit: int = 65536) -> string {
	wide: ^u16
	if (cast(proc "system" (^COM, ^^u16) -> win.HRESULT)object.v[slot])(object, &wide) < 0 || wide == nil { return "" }
	defer win.CoTaskMemFree(wide)
	count := 0
	for count < limit && (cast([^]u16)wide)[count] != 0 { count += 1 }
	if count == limit { return "" }
	return win.utf16_to_utf8((cast([^]u16)wide)[:count]) or_else ""
}
