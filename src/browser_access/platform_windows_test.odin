package browser_access

import "core:fmt"
import "core:os"
import "core:testing"
import win "core:sys/windows"

when ODIN_TEST {
	@(test)
	dpapi_cache_roundtrip_invalidation_and_forget :: proc(t: ^testing.T) {
		directory, err := os.make_directory_temp("", "krodin-access-test-", context.allocator)
		if !testing.expect(t, err == nil) { return }
		defer delete(directory)
		defer os.remove_all(directory)
		legacy := fmt.aprintf("%s\\access.dpapi", directory); defer delete(legacy)
		testing.expect(t, os.write_entire_file(legacy, []byte{1,2,3}) == nil)
		old := cache_load(directory); defer delete(old)
		testing.expect(t, len(old) == 0, "caches created without the username gate must be ignored")
		token := fixture_token(`{"exp":4102444800}`); defer delete(token)
		if !testing.expect(t, cache_save(token, directory)) { return }
		loaded := cache_load(directory); defer delete(loaded)
		testing.expect(t, loaded == token)
		encrypted, read_err := os.read_entire_file_from_path(fmt.tprintf("%s\\%s", directory, CACHE_NAME), context.allocator)
		defer delete(encrypted)
		testing.expect(t, read_err == nil && string(encrypted) != token)
		if len(encrypted) > 0 {
			encrypted[len(encrypted)-1] ~= 0xFF
			plain, valid := protect(encrypted, false); defer delete(plain)
			testing.expect(t, !valid, "corrupt ciphertext must not be accepted")
		}
		cache_invalidate(directory)
		missing := cache_load(directory); defer delete(missing)
		testing.expect(t, len(missing) == 0)
		testing.expect(t, cache_save(token, directory))
		profile := fmt.tprintf("%s\\Browser", directory)
		testing.expect(t, os.make_directory(profile) == nil)
		testing.expect(t, os.write_entire_file(fmt.tprintf("%s\\session", profile), []byte{1,2,3}) == nil)
		testing.expect(t, forget(directory))
		testing.expect(t, !os.is_dir(profile) && !os.is_file(fmt.tprintf("%s\\%s", directory, CACHE_NAME)))
		testing.expect(t, !os.is_file(legacy), "Forget also removes the legacy token cache")
	}
	@(test)
	private_pipe_drains_messages_after_helper_exit :: proc(t: ^testing.T) {
		read, write: win.HANDLE
		if !testing.expect(t, bool(win.CreatePipe(&read, &write, nil, MAX_MESSAGE))) { return }
		defer win.CloseHandle(read)
		testing.expect(t, send(write, Message{42, "STATUS", "VISIBLE"}))
		testing.expect(t, send(write, Message{42, "ERROR", "CANCELLED"}))
		win.CloseHandle(write)
		buffer: [dynamic]byte; defer delete(buffer)
		for kind in ([]string{"STATUS", "ERROR"}) {
			message, ready, alive := receive(read, &buffer)
			testing.expect(t, ready && alive && message.id == 42 && message.kind == kind)
			delete(message.kind); delete(message.value)
		}
		_, _, alive := receive(read, &buffer)
		testing.expect(t, !alive)
	}
	@(test)
	pipe_rejects_malformed_messages :: proc(t: ^testing.T) {
		buffer: [dynamic]byte; defer delete(buffer)
		append(&buffer, `{"id":42,"kind":"TOKEN"`)
		_, ready, alive := pop_message(&buffer)
		testing.expect(t, !ready && alive)
		append(&buffer, "}\n")
		message, complete, valid := pop_message(&buffer)
		testing.expect(t, complete && valid && message.id == 42)
		delete(message.kind); delete(message.value)
		append(&buffer, "invalid json\n")
		_, _, good := pop_message(&buffer)
		testing.expect(t, !good)
	}
}
