package lib
import "base:intrinsics"
import "core:bytes"

// constants
@(private)
_ASCII_MAX_CHAR :: 0x7f
#assert((_ASCII_MAX_CHAR >> 6) < len(_AsciiBitset))

// types
@(private)
_AsciiBitset :: distinct [2]u64
@(private)
_ascii_bit_set :: proc(ascii_chars: string) -> (ascii_set: _AsciiBitset) #no_bounds_check {
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
index_ascii :: proc "contextless" (str: string, char: byte) -> (byte_index: int) {
	/* TODO: do SIMD in a better way */
	index_or_err := #force_inline bytes.index_byte(transmute([]u8)str, char)
	return index_or_err == -1 ? len(str) : index_or_err
}
index_ascii_after :: proc "contextless" (str: string, char: byte) -> (byte_index: int) {
	return index_ascii(str, char) + 1
}
last_index_ascii :: proc "contextless" (str: string, char: byte) -> (byte_index: int) {
	index_or_err := #force_inline bytes.last_index_byte(transmute([]u8)str, char)
	return index_or_err
}

index_any_ascii :: proc(str: string, ascii_chars: string) -> int {
	if len(ascii_chars) == 1 {
		return index_ascii(str, ascii_chars[0])
	} else {
		as := _ascii_bit_set(ascii_chars)
		for i in 0 ..< len(str) {
			if _ascii_bitset_contains(as, str[i]) {return i}
		}
		return len(str)
	}
}
index_any_ascii_after :: proc(str: string, ascii_chars: string) -> int {
	return index_any_ascii(str, ascii_chars) + 1
}
