package lib
import "core:fmt"

@(require_results)
get_args :: proc(allocator := context.temp_allocator) -> (args: [dynamic]string) {
	args.allocator = allocator
	when ODIN_OS == .Windows {
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
			append(&args, copy_cwstr_to_string(&wargs[i], j - i, allocator = allocator))

			i = j
			if end_char != 0 && wargs[j] == end_char {
				i += 1
			}
			for wargs[i] != 0 && (wargs[i] == ' ' || wargs[i] == '\t') {
				i += 1
			}
		}
	} else when ODIN_OS == .Linux {
		args_file, ok := read_file("/proc/self/cmdline", allocator = allocator)
		fmt.assertf(ok, "Failed to read command line arguments")
		i := 0
		for c, j in args_file {
			if c == 0 {
				append(&args, args_file[i:j])
				i = j + 1
			}
		}
	} else {
		assert(false)
	}
	return
}
exit_process :: proc(exit_code: u32 = 0) {
	when ODIN_OS == .Windows {
		ExitProcess(exit_code)
	} else when ODIN_OS == .Linux {
		exit(i32(exit_code))
	} else {
		assert(false)
	}
}
