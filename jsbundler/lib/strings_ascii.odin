package lib
import "core:bytes"

// constants
@(private)
_ASCII_MAX_CHAR :: 0x7f
#assert((_ASCII_MAX_CHAR >> 6) < len(_AsciiBitset))

// types
@(private)
_AsciiBitset :: distinct [2]u64
@(private)
_ascii_bitset :: proc(ascii_chars: string) -> (ascii_set: _AsciiBitset) #no_bounds_check {
	for i in 0 ..< len(ascii_chars) {
		char := ascii_chars[i]
		assert(char <= _ASCII_MAX_CHAR)
		ascii_set[char >> 6] |= 1 << uint(char & 63)
	}
	return
}

// helper procs
@(private)
_ascii_bitset_contains :: proc(as: _AsciiBitset, char: byte) -> bool #no_bounds_check {
	return as[char >> 6] & (1 << (char & 63)) != 0
}

// procs
index_ascii_char :: proc "contextless" (
	str: string,
	start: int,
	ascii_char: byte,
) -> (
	middle: int,
) {
	/* TODO: do SIMD in a better way */
	slice := str[start:]
	index_or_err := #force_inline bytes.index_byte(transmute([]u8)str, ascii_char)
	return index_or_err == -1 ? len(str) : start + index_or_err
}
index_ascii :: proc(str: string, start: int, ascii_chars: string) -> (middle: int) {
	if len(ascii_chars) == 1 {
		return index_ascii_char(str, start, ascii_chars[0])
	} else {
		as := _ascii_bitset(ascii_chars)
		for i in start ..< len(str) {
			if _ascii_bitset_contains(as, str[i]) {return i}
		}
		return len(str)
	}
}
index_ignore_newline :: proc(str: string, start: int) -> (end: int) {
	j := start
	if j < len(str) && str[j] == '\r' {j += 1}
	if j < len(str) && str[j] == '\n' {j += 1}
	return j
}
index_ignore_newlines :: proc(str: string, start: int) -> (end: int) {
	j := start
	for j < len(str) && (str[j] == '\r' || str[j] == '\n') {
		j += 1
	}
	return j
}
last_index_ascii_char :: proc "contextless" (str: string, ascii_char: byte) -> (start: int) {
	/* TODO: do SIMD in a better way */
	index_or_err := #force_inline bytes.last_index_byte(transmute([]u8)str, ascii_char)
	return index_or_err == -1 ? -1 : index_or_err
}
