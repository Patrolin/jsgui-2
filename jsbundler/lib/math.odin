package lib
import intrinsics "base:intrinsics"

// constants
Byte :: Size(1)
KibiByte :: Size(1024 * Byte)
MebiByte :: Size(1024 * KibiByte)
GibiByte :: Size(1024 * MebiByte)

/* NOTE: *NOT* the max path on windows anymore, but half the apis don't support paths above this... */
WINDOWS_MAX_PATH :: 260

// types
Size :: distinct int

IS_32BIT :: ODIN_ARCH == .i386 || ODIN_ARCH == .arm32 || ODIN_ARCH == .wasm32
IS_64BIT :: ODIN_ARCH == .amd64 || ODIN_ARCH == .arm64 || ODIN_ARCH == .riscv64 || ODIN_ARCH == .wasm64p32

CSHORT :: i16
CUSHORT :: u16
when IS_32BIT {
	CINT :: i16
	CUINT :: u16
} else when IS_64BIT {
	CINT :: i32
	CUINT :: u32
} else {
	#assert(false)
}
CLONG :: i32
CULONG :: u32
CLONGLONG :: i64
CULONGLONG :: u64

// int procs
ptr_add :: #force_inline proc "contextless" (ptr: rawptr, offset: int) -> [^]byte {
	return ([^]byte)(uintptr(ptr) + uintptr(offset))
}
count_leading_zeros :: intrinsics.count_leading_zeros
count_trailing_zeros :: intrinsics.count_trailing_zeros
count_ones :: intrinsics.count_ones
count_zeros :: intrinsics.count_zeros
/* AKA find_first_set() */
log2_floor :: #force_inline proc "contextless" (x: $T) -> T where intrinsics.type_is_unsigned(T) {
	return x > 0 ? size_of(T) * 8 - 1 - count_leading_zeros(x) : 0
}
log2_ceil :: #force_inline proc "contextless" (x: $T) -> T where intrinsics.type_is_unsigned(T) {
	return x > 1 ? size_of(T) * 8 - 1 - count_leading_zeros((x - 1) << 1) : 0
}

// float procs
@(private)
split_float_any :: proc "contextless" (x: $F, mask, shift, bias: $U) -> (int, frac: F) {
	#assert(size_of(F) == size_of(U))
	negate := x < 0
	x := negate ? -x : x

	if x < 1 {return 0, negate ? -x : x}

	i := transmute(U)x
	e := (i >> shift) & mask - bias

	if e < shift {i &~= 1 << (shift - e) - 1}
	int = transmute(F)i
	frac = x - int
	return negate ? -int : int, negate ? -frac : frac
}
split_float_f16 :: proc "contextless" (x: f16) -> (int: f16, frac: f16) {
	return split_float_any(x, u16(0x1f), 16 - 6, 0xf)
}
split_float_f32 :: proc "contextless" (x: f32) -> (int: f32, frac: f32) {
	return split_float_any(x, u32(0xff), 32 - 9, 0x7f)
}
split_float_f64 :: proc "contextless" (x: f64) -> (int: f64, frac: f64) {
	return split_float_any(x, u64(0x7ff), 64 - 12, 0x3ff)
}
split_float :: proc {
	split_float_f16,
	split_float_f32,
	split_float_f64,
}
