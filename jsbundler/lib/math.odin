package lib
import intrinsics "base:intrinsics"

// constants
Byte :: Size(1)
KibiByte :: Size(1024 * Byte)
MebiByte :: Size(1024 * KibiByte)
GibiByte :: Size(1024 * MebiByte)

// types
Size :: distinct int

// int procedures
ptr_add :: #force_inline proc "contextless" (ptr: rawptr, offset: int) -> [^]byte {
	return ([^]byte)(uintptr(ptr) + uintptr(offset))
}
count_leading_zeros :: intrinsics.count_leading_zeros
count_trailing_zeros :: intrinsics.count_trailing_zeros
count_ones :: intrinsics.count_ones
count_zeros :: intrinsics.count_zeros
is_power_of_two :: #force_inline proc "contextless" (
	x: $T,
) -> bool where intrinsics.type_is_integer(T) {
	return count_ones(x) == 1
}
low_mask :: #force_inline proc "contextless" (
	power_of_two: $T,
) -> T where intrinsics.type_is_unsigned(T) {
	return power_of_two - 1
}
high_mask :: #force_inline proc "contextless" (
	power_of_two: $T,
) -> T where intrinsics.type_is_unsigned(T) {
	return ~(power_of_two - 1)
}
get_bit :: #force_inline proc "contextless" (
	x, bit_index: $T,
) -> T where intrinsics.type_is_unsigned(T) {
	return (x >> bit_index) & 1
}
set_bit_one :: #force_inline proc "contextless" (
	x, bit_index: $T,
) -> T where intrinsics.type_is_unsigned(T) {
	return x | (1 << bit_index)
}
set_bit_zero :: #force_inline proc "contextless" (
	x, bit_index: $T,
) -> T where intrinsics.type_is_unsigned(T) {
	return x & ~(1 << bit_index)
}
set_bit :: #force_inline proc "contextless" (
	x, bit_index, bit_value: $T,
) -> T where intrinsics.type_is_unsigned(T) {
	x_without_bit := x & ~(1 << bit_index)
	bit := ((bit_value & 1) << bit_index)
	return x | bit
	//toggle_bit := ((x >> bit_index) ~ bit_value) & 1
	//return x ~ (toggle_bit << bit_index)
}
/* AKA find_first_set() */
log2_floor :: #force_inline proc "contextless" (x: $T) -> T where intrinsics.type_is_unsigned(T) {
	return x > 0 ? size_of(T) * 8 - 1 - count_leading_zeros(x) : 0
}
log2_ceil :: #force_inline proc "contextless" (x: $T) -> T where intrinsics.type_is_unsigned(T) {
	return x > 1 ? size_of(T) * 8 - 1 - count_leading_zeros((x - 1) << 1) : 0
}

// float procedures
@(private)
_split_float_any :: proc "contextless" (x: $F, mask, shift, bias: $U) -> (int, frac: F) {
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
	return _split_float_any(x, u16(0x1f), 16 - 6, 0xf)
}
split_float_f32 :: proc "contextless" (x: f32) -> (int: f32, frac: f32) {
	return _split_float_any(x, u32(0xff), 32 - 9, 0x7f)
}
split_float_f64 :: proc "contextless" (x: f64) -> (int: f64, frac: f64) {
	return _split_float_any(x, u64(0x7ff), 64 - 12, 0x3ff)
}
split_float :: proc {
	split_float_f16,
	split_float_f32,
	split_float_f64,
}
