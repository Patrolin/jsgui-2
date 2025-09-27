package lib
import "base:intrinsics"
import "core:fmt"
import "core:strings"

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

/* returns the first byte offset of the first `substring` in the `str`, or `len(str)` when not found. */
@(private)
hash_rabin_karp :: #force_inline proc "contextless" (hash, value: u32) -> u32 {
	return hash * PRIME_RABIN_KARP + value
}
index :: proc "contextless" (str, substring: string) -> (byte_index: int) {
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
	// setup
	hash, str_hash: u32
	for i := 0; i < n; i += 1 {
		hash = hash_rabin_karp(hash, u32(substring[i]))
	}
	for i := 0; i < n; i += 1 {
		str_hash = hash_rabin_karp(str_hash, u32(str[i]))
	}
	if str_hash == hash && str[:n] == substring {
		return 0
	}
	// rolling hash
	pow: u32 = 1
	sq := u32(PRIME_RABIN_KARP)
	for i := n; i > 0; i >>= 1 {
		if (i & 1) != 0 {pow *= sq}
		sq *= sq
	}
	for i := n; i < len(str); {
		str_hash = hash_rabin_karp(str_hash, u32(str[i])) - pow * u32(str[i - n])
		i += 1
		if str_hash == hash && str[i - n:i] == substring {
			return i - n
		}
	}
	return len(str)
}
/* returns the first byte offset of the first `substring` in the `str`, or `len(str)` when not found. */
index_multi :: proc(str: string, substrings: ..string) -> (byte_index: int) {
	// find smallest substring
	smallest_substring := substrings[0]
	for substr in substrings[1:] {
		if len(substr) < len(smallest_substring) {
			smallest_substring = substr
		}
	}
	if intrinsics.expect(len(smallest_substring) == 0, false) {return 0}
	n := len(smallest_substring)
	// setup
	hashes: [16]u32
	k := len(substrings)
	assert(k <= len(hashes))
	for j in 0 ..< k {
		substr := substrings[j]
		hash: u32
		for i := 0; i < n; i += 1 {
			hash = hash_rabin_karp(hash, u32(substr[i]))
		}
		hashes[j] = hash
	}
	str_hash: u32
	for i := 0; i < n; i += 1 {
		str_hash = hash_rabin_karp(str_hash, u32(str[i]))
	}
	for j in 0 ..< k {
		if str_hash != hashes[j] {continue}
		substr := substrings[j]
		end := min(len(substr), len(str))
		if str[:end] == substr {return 0}
	}
	// rolling hash
	pow: u32 = 1
	sq := u32(PRIME_RABIN_KARP)
	for i := n; i > 0; i >>= 1 {
		if (i & 1) != 0 {pow *= sq}
		sq *= sq
	}
	for i := n; i < len(str); {
		str_hash = hash_rabin_karp(str_hash, u32(str[i])) - pow * u32(str[i - n])
		i += 1
		for j in 0 ..< k {
			if str_hash != hashes[j] {continue}
			substr := substrings[j]
			end := min(i - n + len(substr), len(str))
			if str[i - n:end] == substr {return i - n}
		}
	}
	return len(str)
}

/* returns the first byte offset of the last `substring` in the `str`, or `-1` when not found. */
last_index :: proc(str, substring: string) -> (byte_index: int) {
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
	// setup
	last := len(str) - n
	hash, str_hash: u32
	for i := n - 1; i >= 0; i -= 1 {
		hash = hash_rabin_karp(hash, u32(substring[i]))
	}
	for i := len(str) - 1; i >= last; i -= 1 {
		str_hash = hash_rabin_karp(str_hash, u32(str[i]))
	}
	if str_hash == hash && str[last:] == substring {
		return last
	}
	// rolling hash
	pow: u32 = 1
	sq := u32(PRIME_RABIN_KARP)
	for i := n; i > 0; i >>= 1 {
		if (i & 1) != 0 {pow *= sq}
		sq *= sq
	}
	for i := last - 1; i >= 0; i -= 1 {
		str_hash = hash_rabin_karp(str_hash, u32(str[i])) - pow * u32(str[i + n])
		if str_hash == hash && str[i:i + n] == substring {
			return i
		}
	}
	return -1
}
