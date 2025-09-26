package lib
import "core:strings"

/* NOTE: mostly copy paste from core:strings */
// constants
@(private)
PRIME_RABIN_KARP: u32 : 16777619

// types
StringBuilder :: strings.Builder

// procs
to_string :: #force_inline proc(sb: StringBuilder) -> string {
	return strings.to_string(sb)
}
starts_with :: proc(str, prefix: string) -> bool {
	return len(str) >= len(prefix) && str[0:len(prefix)] == prefix
}
ends_with :: proc(str, suffix: string) -> bool {
	return len(str) >= len(suffix) && str[len(str) - len(suffix):] == suffix
}

/* Returns the first byte offset of the `substring` in the `str`, or `len(s)` when not found. */
index :: proc "contextless" (str, substring: string) -> (byte_index: int) {
	hash_str_rabin_karp :: proc "contextless" (s: string) -> (hash: u32 = 0, pow: u32 = 1) {
		for i := 0; i < len(s); i += 1 {
			hash = hash * PRIME_RABIN_KARP + u32(s[i])
		}
		sq := u32(PRIME_RABIN_KARP)
		for i := len(s); i > 0; i >>= 1 {
			if (i & 1) != 0 {
				pow *= sq
			}
			sq *= sq
		}
		return
	}

	n := len(substring)
	switch {
	case n == 0:
		return 0
	case n == 1:
		return index_ascii(str, substring[0])
	case n == len(str):
		return str == substring ? 0 : len(str)
	case n > len(str):
		return len(str)
	}

	hash, pow := hash_str_rabin_karp(substring)
	h: u32
	for i := 0; i < n; i += 1 {
		h = h * PRIME_RABIN_KARP + u32(str[i])
	}
	if h == hash && str[:n] == substring {
		return 0
	}
	for i := n; i < len(str); {
		h *= PRIME_RABIN_KARP
		h += u32(str[i])
		h -= pow * u32(str[i - n])
		i += 1
		if h == hash && str[i - n:i] == substring {
			return i - n
		}
	}
	return len(str)
}

/* Returns the last byte offset of the `substring` in the `str`, or `-1` when not found. */
last_index :: proc(str, substring: string) -> (byte_index: int) {
	hash_str_rabin_karp_reverse :: proc(s: string) -> (hash: u32 = 0, pow: u32 = 1) {
		for i := len(s) - 1; i >= 0; i -= 1 {
			hash = hash * PRIME_RABIN_KARP + u32(s[i])
		}
		sq := u32(PRIME_RABIN_KARP)
		for i := len(s); i > 0; i >>= 1 {
			if (i & 1) != 0 {
				pow *= sq
			}
			sq *= sq
		}
		return
	}

	n := len(substring)
	switch {
	case n == 0:
		return len(str)
	case n == 1:
		return last_index_ascii(str, substring[0])
	case n == len(str):
		return str == substring ? 0 : -1
	case n > len(str):
		return -1
	}

	hash, pow := hash_str_rabin_karp_reverse(substring)
	last := len(str) - n
	h: u32
	for i := len(str) - 1; i >= last; i -= 1 {
		h = h * PRIME_RABIN_KARP + u32(str[i])
	}
	if h == hash && str[last:] == substring {
		return last
	}

	for i := last - 1; i >= 0; i -= 1 {
		h *= PRIME_RABIN_KARP
		h += u32(str[i])
		h -= pow * u32(str[i + n])
		if h == hash && str[i:i + n] == substring {
			return i
		}
	}
	return -1
}
