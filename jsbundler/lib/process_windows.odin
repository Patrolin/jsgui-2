package lib
import "core:fmt"

// process procs
get_args :: proc(allocator := context.temp_allocator) -> (args: [dynamic]string) {
	wargs := GetCommandLineW()
	wbuf := transmute([^]u16)(wargs)

	i := 0
	for wbuf[i] != 0 && (wbuf[i] == ' ' || wbuf[i] == '\t') { 	// NOTE: windows strings are encoded in UTF16LE
		i += 1
	}
	for wbuf[i] != 0 {
		end_char := u16(0)
		if wbuf[i] == '"' {
			end_char = '"'
			i += 1
		} else if wbuf[i] == '\'' {
			end_char = '\''
			i += 1
		}
		j := i
		for wbuf[j] != 0 && (wbuf[j] != end_char) {
			j += 1
		}
		warg := string16(wbuf[i:j])
		append(&args, tprint_wstring(warg, allocator = allocator))

		i = j
		if end_char != 0 && wbuf[j] == end_char {
			i += 1
		}
		for wbuf[i] != 0 && (wbuf[i] == ' ' || wbuf[i] == '\t') {
			i += 1
		}
	}
	return
}
exit_process :: proc(exit_code: u32 = 0) {
	ExitProcess(exit_code)
}
