package browser_access

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"

Blob :: struct { size: u32, data: ^byte }
// Older builds accepted tokens without checking krunker_username. Ignore their cache.
CACHE_NAME :: "access-account.dpapi"
foreign import crypt "system:crypt32.lib"
@(default_calling_convention="system")
foreign crypt {
	CryptProtectData :: proc(input: ^Blob, description: ^u16, entropy: ^Blob, reserved, prompt: rawptr, flags: u32, output: ^Blob) -> win.BOOL ---
	CryptUnprotectData :: proc(input: ^Blob, description: ^^u16, entropy: ^Blob, reserved, prompt: rawptr, flags: u32, output: ^Blob) -> win.BOOL ---
}

root_path :: proc() -> string {
	local, ok := os.lookup_env_alloc("LOCALAPPDATA", context.allocator)
	defer delete(local)
	if !ok || len(local) == 0 { return "" }
	return fmt.aprintf("%s\\Krodin", local)
}

protect :: proc(data: []byte, encrypt: bool) -> ([]byte, bool) {
	if len(data) == 0 || len(data) > MAX_MESSAGE { return nil, false }
	input := Blob{u32(len(data)), raw_data(data)}
	output: Blob
	ok := encrypt ? CryptProtectData(&input, nil, nil, nil, nil, 1, &output) : CryptUnprotectData(&input, nil, nil, nil, nil, 1, &output)
	if !ok { return nil, false }
	defer win.LocalFree(win.HGLOBAL(output.data))
	copy_data := make([]byte, int(output.size))
	copy(copy_data, (cast([^]byte)output.data)[:output.size])
	return copy_data, true
}

cache_load :: proc(directory: string = "") -> string {
	root := len(directory) > 0 ? strings.clone(directory) : root_path(); defer delete(root)
	if len(root) == 0 { return "" }
	path := fmt.tprintf("%s\\%s", root, CACHE_NAME)
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil { return "" }
	defer delete(data)
	plain, ok := protect(data, false)
	if !ok { return "" }
	return string(plain)
}

cache_save :: proc(token: string, directory: string = "") -> bool {
	root := len(directory) > 0 ? strings.clone(directory) : root_path(); defer delete(root)
	if len(root) == 0 { return false }
	if os.make_directory(root) != nil && !os.is_dir(root) { return false }
	data, ok := protect(transmute([]byte)token, true)
	if !ok { return false }
	defer delete(data)
	path := fmt.tprintf("%s\\%s", root, CACHE_NAME)
	return os.write_entire_file(path, data) == nil
}

cache_invalidate :: proc(directory: string = "") -> bool {
	root := len(directory) > 0 ? strings.clone(directory) : root_path(); defer delete(root)
	if len(root) == 0 { return false }
	path := fmt.tprintf("%s\\%s", root, CACHE_NAME)
	if !os.is_file(path) { return true }
	return os.remove(path) == nil
}

forget :: proc(directory: string = "") -> bool {
	root := len(directory) > 0 ? strings.clone(directory) : root_path(); defer delete(root)
	if len(root) == 0 { return false }
	if !cache_invalidate(root) { return false }
	legacy := fmt.tprintf("%s\\access.dpapi", root)
	if os.is_file(legacy) && os.remove(legacy) != nil { return false }
	profile := fmt.tprintf("%s\\Browser", root)
	if os.is_dir(profile) && os.remove_all(profile) != nil { return false }
	return true
}

Child :: struct {
	process, input, output: win.HANDLE,
	buffer: [dynamic]byte,
}

// Restrict inheritance to the two private pipe ends, even if the client owns other inheritable handles.
Extended_Startup :: struct { startup: win.STARTUPINFOW, attributes: rawptr }
foreign import kernel "system:kernel32.lib"
@(default_calling_convention="system")
foreign kernel {
	InitializeProcThreadAttributeList :: proc(list: rawptr, count, flags: u32, size: ^uintptr) -> win.BOOL ---
	UpdateProcThreadAttribute :: proc(list: rawptr, flags: u32, attribute: uintptr, value: rawptr, size: uintptr, previous, returned: rawptr) -> win.BOOL ---
	DeleteProcThreadAttributeList :: proc(list: rawptr) ---
}

start :: proc(child: ^Child, id: u64, hidden: bool, kind: string = "", value: string = "") -> bool {
	if child.process != nil { return false }
	var_read, var_write: win.HANDLE
	out_read, out_write: win.HANDLE
	sa := win.SECURITY_ATTRIBUTES{nLength = size_of(win.SECURITY_ATTRIBUTES), bInheritHandle = true}
	if !win.CreatePipe(&var_read, &var_write, &sa, MAX_MESSAGE) { return false }
	defer win.CloseHandle(var_read)
	if !win.CreatePipe(&out_read, &out_write, &sa, MAX_MESSAGE) { win.CloseHandle(var_write); return false }
	defer win.CloseHandle(out_write)
	success := false
	defer { if !success { win.CloseHandle(var_write); win.CloseHandle(out_read) } }
	if !win.SetHandleInformation(var_write, win.HANDLE_FLAG_INHERIT, 0) || !win.SetHandleInformation(out_read, win.HANDLE_FLAG_INHERIT, 0) { return false }
	size: uintptr
	InitializeProcThreadAttributeList(nil, 1, 0, &size)
	attrs := make([]byte, int(size)); defer delete(attrs)
	if !InitializeProcThreadAttributeList(raw_data(attrs), 1, 0, &size) { return false }
	defer DeleteProcThreadAttributeList(raw_data(attrs))
	handles := [2]win.HANDLE{var_read, out_write}
	if !UpdateProcThreadAttribute(raw_data(attrs), 0, 0x20002, &handles, size_of(handles), nil, nil) { return false }
	directory, err := os.get_executable_directory(context.temp_allocator)
	if err != nil { return false }
	exe := win.utf8_to_utf16(fmt.tprintf("%s\\krodin_browser.exe", directory))
	command := win.utf8_to_utf16(fmt.tprintf("\"%s\\krodin_browser.exe\"", directory))
	si := Extended_Startup{startup = {cb = size_of(Extended_Startup), dwFlags = win.STARTF_USESTDHANDLES, hStdInput = var_read, hStdOutput = out_write}, attributes = raw_data(attrs)}
	pi: win.PROCESS_INFORMATION
	if !win.CreateProcessW(cast(cstring16)raw_data(exe), cast(cstring16)raw_data(command), nil, nil, true, win.CREATE_NO_WINDOW | win.EXTENDED_STARTUPINFO_PRESENT, nil, nil, &si.startup, &pi) { return false }
	win.CloseHandle(pi.hThread)
	child^ = {process = pi.hProcess, input = var_write, output = out_read}
	success = true
	return send(child.input, Message{id, len(kind) > 0 ? kind : hidden ? "REFRESH" : "JOIN", value})
}

send :: proc(handle: win.HANDLE, message: Message) -> bool {
	data, err := json.marshal(message)
	if err != nil { return false }
	defer delete(data)
	if len(data) > MAX_MESSAGE-1 { return false }
	written: u32
	if !win.WriteFile(handle, raw_data(data), u32(len(data)), &written, nil) || int(written) != len(data) { return false }
	newline := byte('\n')
	return bool(win.WriteFile(handle, &newline, 1, &written, nil))
}

// Nonblocking, bounded framing. The caller owns message strings on success.
receive :: proc(handle: win.HANDLE, buffer: ^[dynamic]byte) -> (message: Message, ready, alive: bool) {
	if message, ready, alive := pop_message(buffer); ready || !alive { return message, ready, alive }
	available: u32
	if !win.PeekNamedPipe(handle, nil, 0, nil, &available, nil) { return {}, false, false }
	if available > 0 {
		if len(buffer^) + int(available) > MAX_MESSAGE { return {}, false, false }
		chunk: [MAX_MESSAGE]byte
		count: u32
		if !win.ReadFile(handle, &chunk, available, &count, nil) { return {}, false, false }
		append(buffer, ..chunk[:count])
	}
	return pop_message(buffer)
}

pop_message :: proc(buffer: ^[dynamic]byte) -> (message: Message, ready, alive: bool) {
	for b, i in buffer^ {
		if b != '\n' { continue }
		err := json.unmarshal(buffer^[:i], &message)
		copy(buffer^[:], buffer^[i+1:])
		resize(buffer, len(buffer^)-i-1)
		if err != nil { delete(message.kind); delete(message.value); return {}, false, false }
		return message, true, true
	}
	return {}, false, true
}

stop :: proc(child: ^Child, id: u64) {
	if child.process != nil {
		send(child.input, Message{id, "CANCEL", ""})
		// Revoking the request in the parent prevents any late reply from joining.
		win.CloseHandle(child.input)
		// The helper observes EOF on its private input and closes WebView2 on its STA thread.
		win.CloseHandle(child.process)
		win.CloseHandle(child.output)
	}
	delete(child.buffer)
	child^ = {}
}
