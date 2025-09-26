package lib
import "base:intrinsics"
import "core:bytes"

/* NOTE: mostly copy paste from core:strings */
// types
@(private)
_Ascii_Set :: distinct [8]u32

// helper procs
@(private)
_ascii_set_make :: proc(ascii_chars: string) -> (ascii_set: _Ascii_Set) #no_bounds_check {
	for i in 0 ..< len(ascii_chars) {
		char := ascii_chars[i]
		assert(char < 0x80)
		ascii_set[char >> 5] |= 1 << uint(char & 31)
	}
	return
}
@(private)
_ascii_set_contains :: proc(as: _Ascii_Set, c: byte) -> bool #no_bounds_check {
	return as[c >> 5] & (1 << (c & 31)) != 0
}

// procs
index_ascii :: proc "contextless" (str: string, char: byte) -> (byte_index: int) {
	/* TODO: do SIMD in a better way */
	index_or_err := #force_inline bytes.index_byte(transmute([]u8)str, char)
	return index_or_err == -1 ? len(str) : index_or_err
}
index_after_ascii :: proc(str: string, char: byte) -> (byte_index: int) #no_bounds_check {
	for i in 0 ..< len(str) {
		if str[i] != char {return i}
	}
	return len(str)
}
last_index_ascii :: proc "contextless" (str: string, char: byte) -> (byte_index: int) {
	index_or_err := #force_inline bytes.last_index_byte(transmute([]u8)str, char)
	return index_or_err
}

index_any_ascii :: proc(str: string, ascii_chars: string) -> int {
	if len(ascii_chars) == 1 {
		return index_ascii(str, ascii_chars[0])
	} else {
		as := _ascii_set_make(ascii_chars)
		for i in 0 ..< len(str) {
			if _ascii_set_contains(as, str[i]) {return i}
		}
		return len(str)
	}
}
index_after_any_ascii :: proc(str: string, ascii_chars: string) -> int {
	if len(ascii_chars) == 1 {
		return index_after_ascii(str, ascii_chars[0])
	} else {
		as := _ascii_set_make(ascii_chars)
		for i in 0 ..< len(str) {
			if !_ascii_set_contains(as, str[i]) {return i}
		}
		return len(str)
	}
}
