package lib
import win "core:sys/windows"

// helper procs
@(private)
_wstring_to_string_cstring :: proc(
	wstr: cstring16,
	allocator := context.temp_allocator,
) -> string {
	res, err := win.wstring_to_utf8_alloc(wstr, -1, allocator = allocator)
	assert(err == nil)
	return res
}
@(private)
_wstring_to_string_slice :: proc(wstr: []u16, allocator := context.temp_allocator) -> string {
	res, err := win.wstring_to_utf8_alloc(
		win.wstring(raw_data(wstr)),
		len(wstr),
		allocator = allocator,
	)
	assert(err == nil)
	return res
}
_wstring_to_string :: proc {
	_wstring_to_string_cstring,
	_wstring_to_string_slice,
}
_string_to_wstring :: proc(str: string, allocator := context.temp_allocator) -> win.wstring {
	return win.utf8_to_wstring(str, allocator = allocator)
}

// arg procs
get_args :: proc(allocator := context.temp_allocator) -> (args: [dynamic]string) {
	wargs := win.GetCommandLineW()
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
		warg := wbuf[i:j]
		append(&args, _wstring_to_string(warg, allocator = allocator))

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
	win.ExitProcess(exit_code)
}
