package lib
import "base:intrinsics"
import "core:fmt"
import "core:mem"

// constants
// NOTE: SSD block sizes are 512B or 4KiB
SSD_BLOCK_SIZE :: 512
VIRTUAL_MEMORY_TO_RESERVE :: 1 << 16

PAGE_SIZE_EXPONENT :: 12
PAGE_SIZE :: 1 << PAGE_SIZE_EXPONENT
#assert(PAGE_SIZE == 4096)

HUGE_PAGE_SIZE_EXPONENT :: 21
HUGE_PAGE_SIZE :: 1 << HUGE_PAGE_SIZE_EXPONENT
#assert(HUGE_PAGE_SIZE == 2_097_152)

// NOTE: multiple threads reading from the same cache line is fine, but writing can lead to false sharing
CACHE_LINE_SIZE_EXPONENT :: 6
CACHE_LINE_SIZE :: 1 << CACHE_LINE_SIZE_EXPONENT
#assert(CACHE_LINE_SIZE == 64)

// types
Lock :: distinct bool

// lock procs
mfence :: #force_inline proc "contextless" () {
	intrinsics.atomic_thread_fence(.Seq_Cst)
}
@(require_results)
get_lock :: #force_inline proc "contextless" (lock: ^Lock) -> (ok: bool) {
	old_value := intrinsics.atomic_exchange(lock, true)
	return old_value == false
}
wait_for_lock :: #force_inline proc "contextless" (lock: ^Lock) {
	for {
		old_value := intrinsics.atomic_exchange(lock, true)
		if intrinsics.expect(old_value == false, true) {return}
		intrinsics.cpu_relax()
	}
	mfence()
}
release_lock :: #force_inline proc "contextless" (lock: ^Lock) {
	intrinsics.atomic_store(lock, false)
}

// copy procs
zero :: proc(buffer: []byte) {
	dest := uintptr(raw_data(buffer))
	dest_end := dest + uintptr(len(buffer))
	dest_end_64B := dest_end & 63
	zero_src := (#simd[64]byte)(0)
	for dest < dest_end_64B {
		(^#simd[64]byte)(dest)^ = zero_src
		dest += 64
	}
	for dest < dest_end {
		(^byte)(dest)^ = 0
		dest += 1
	}
}
copy :: proc(from, to: []byte) {
	src := uintptr(raw_data(from))
	dest := uintptr(raw_data(to))
	dest_end := dest + uintptr(min(len(from), len(to)))
	dest_end_64B := dest_end & 63
	for dest < dest_end_64B {
		(^#simd[64]byte)(dest)^ = (^#simd[64]byte)(src)^
		dest += 64
		src += 64
	}
	for dest < dest_end {
		(^byte)(dest)^ = (^byte)(src)^
		dest += 1
		src += 1
	}
}

// arena types
ArenaAllocator :: struct {
	buffer_start: uintptr,
	buffer_end:   uintptr,
	next_ptr:     uintptr,
	/* NOTE: for asserting single-threaded */
	lock:         Lock,
}

// arena procs
arena_allocator :: proc(arena_allocator: ^ArenaAllocator, buffer: []byte) -> mem.Allocator {
	buffer_start := uintptr(raw_data(buffer))
	buffer_end := buffer_start + uintptr(len(buffer))
	arena_allocator^ = ArenaAllocator{buffer_start, buffer_end, buffer_start, false}
	return mem.Allocator{arena_allocator_proc, arena_allocator}
}
arena_allocator_proc :: proc(
	allocator: rawptr,
	mode: mem.Allocator_Mode,
	size, _alignment: int,
	old_ptr: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	data: []byte,
	err: mem.Allocator_Error,
) {
	arena_allocator := (^ArenaAllocator)(allocator)
	// assert single threaded
	ok := get_lock(&arena_allocator.lock)
	assert(ok, loc = loc)
	defer release_lock(&arena_allocator.lock)

	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		// alloc
		data = _arena_alloc(arena_allocator, size)
		if intrinsics.expect(arena_allocator.next_ptr > arena_allocator.buffer_end, false) {
			err = .Out_Of_Memory
			break
		}
		// zero
		if mode == .Alloc {zero(data)}
	case .Resize, .Resize_Non_Zeroed:
		new_section_ptr := uintptr(old_ptr) + uintptr(old_size)
		if new_section_ptr == arena_allocator.next_ptr {
			// resize in place
			data = ([^]byte)(old_ptr)[:size]
			arena_allocator.next_ptr = uintptr(old_ptr) + uintptr(size)
			if intrinsics.expect(arena_allocator.next_ptr > arena_allocator.buffer_end, false) {
				err = .Out_Of_Memory
				break
			}
			if intrinsics.expect(size > old_size, true) {
				new_section := ([^]byte)(new_section_ptr)[:size - old_size]
				if mode == .Resize {zero(new_section)}
			}
		} else {
			// alloc
			data = _arena_alloc(arena_allocator, size)
			if intrinsics.expect(arena_allocator.next_ptr > arena_allocator.buffer_end, false) {
				err = .Out_Of_Memory
				break
			}
			// copy
			old_data := ([^]byte)(old_ptr)[:old_size]
			if mode == .Resize {zero(data)}
			copy(old_data, data)
		}
	case .Free_All:
		arena_allocator.next_ptr = arena_allocator.buffer_start
	}
	return
}
@(private)
_arena_alloc :: proc(arena_allocator: ^ArenaAllocator, size: int) -> []byte {
	ptr := arena_allocator.next_ptr
	// NOTE: align forward to 64B, so we can do faster simd ops
	ARENA_ALIGN :: 64
	remainder := ptr & (ARENA_ALIGN - 1)
	align_offset: uintptr
	if remainder != 0 {align_offset = ARENA_ALIGN - remainder}
	ptr += align_offset
	// update allocator
	arena_allocator.next_ptr = ptr + uintptr(size)
	return ([^]byte)(ptr)[:size]
}
