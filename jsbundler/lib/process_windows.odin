package lib
import "core:fmt"

// process procs
get_args :: proc(allocator := context.temp_allocator) -> (args: [dynamic]string) {
	wargs := GetCommandLineW()
	i := 0
	for wargs[i] != 0 && (wargs[i] == ' ' || wargs[i] == '\t') {
		i += 1
	}
	for wargs[i] != 0 {
		end_char := u16(0)
		if wargs[i] == '"' {
			end_char = '"'
			i += 1
		} else if wargs[i] == '\'' {
			end_char = '\''
			i += 1
		}
		j := i
		for wargs[j] != 0 && (wargs[j] != end_char) {
			j += 1
		}
		warg := string16(wargs[i:j])
		append(&args, tprint_wstring(warg, allocator = allocator))

		i = j
		if end_char != 0 && wargs[j] == end_char {
			i += 1
		}
		for wargs[i] != 0 && (wargs[i] == ' ' || wargs[i] == '\t') {
			i += 1
		}
	}
	return
}
exit_process :: proc(exit_code: u32 = 0) {
	ExitProcess(exit_code)
}
