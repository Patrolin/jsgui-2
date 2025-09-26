package lib
import "base:intrinsics"
import "core:mem"

// constants
// NOTE: SSD block sizes are 512B or 4KiB
SSD_BLOCK_SIZE :: 512
VIRTUAL_MEMORY_TO_RESERVE :: 1 << 16

PAGE_SIZE_EXPONENT :: 12
PAGE_SIZE :: 1 << PAGE_SIZE_EXPONENT

HUGE_PAGE_SIZE_EXPONENT :: 21
HUGE_PAGE_SIZE :: 1 << HUGE_PAGE_SIZE_EXPONENT

// NOTE: multiple threads reading from the same cache line is fine, but writing can lead to false sharing
CACHE_LINE_SIZE_EXPONENT :: 6
CACHE_LINE_SIZE :: 1 << CACHE_LINE_SIZE_EXPONENT

// types
Lock :: distinct bool
ArenaAllocator :: struct {
	buffer: []byte `fmt:"%p"`,
	next:   int,
	/* we will assume single threaded, this is just here to catch bugs */
	lock:   Lock,
}

// lock procedures
mfence :: #force_inline proc "contextless" () {
	intrinsics.atomic_thread_fence(.Seq_Cst)
}
@(require_results)
get_lock_or_error :: #force_inline proc "contextless" (lock: ^Lock) -> (ok: bool) {
	old_value := intrinsics.atomic_exchange(lock, true)
	return old_value == false
}
get_lock :: #force_inline proc "contextless" (lock: ^Lock) {
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

// copy procedures
copy_slow :: proc(src: rawptr, size: int, dest: rawptr) {
	dest := uintptr(dest)
	dest_end := dest + transmute(uintptr)(size)
	src := uintptr(src)
	for dest < dest_end {
		(^byte)(dest)^ = (^byte)(src)^
		dest += 1
		src += 1
	}
}
zero_simd_64B :: proc(dest: rawptr, size: int) {
	dest := uintptr(dest)
	dest_end := dest + transmute(uintptr)(size)

	zero := (#simd[64]byte)(0)
	for dest < dest_end {
		(^#simd[64]byte)(dest)^ = zero
		dest += 64
	}
}
copy_simd_64B :: proc(src: rawptr, size: int, dest: rawptr) {
	dest := uintptr(dest)
	dest_end := dest + transmute(uintptr)(size)
	src := uintptr(src)

	for dest < dest_end {
		(^#simd[64]byte)(dest)^ = (^#simd[64]byte)(src)^
		dest += 64
		src += 64
	}
}

// arena procedures
arena_allocator :: proc(arena_allocator: ^ArenaAllocator, buffer: []byte) -> mem.Allocator {
	arena_allocator^ = ArenaAllocator{buffer, 0, false}
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
	DEBUG :: false
	when DEBUG {fmt.printfln("mode: %v, size: %v, loc: %v", mode, size, loc)}

	arena_allocator := (^ArenaAllocator)(allocator)
	// assert single threaded
	ok := get_lock_or_error(&arena_allocator.lock)
	assert(ok, loc = loc)
	defer release_lock(&arena_allocator.lock)

	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		ptr := _arena_alloc(arena_allocator, size)
		data = ptr[:size]
		err = arena_allocator.next > len(arena_allocator.buffer) ? .Out_Of_Memory : .None
	case .Resize, .Resize_Non_Zeroed:
		// alloc
		ptr := _arena_alloc(arena_allocator, size)
		data = ptr[:size]
		if (intrinsics.expect(arena_allocator.next > len(arena_allocator.buffer), false)) {
			err = .Out_Of_Memory
			break
		}
		// copy
		size_to_copy := min(size, old_size)
		copy_simd_64B(old_ptr, size_to_copy, ptr)
	case .Free_All:
		arena_allocator.next = 0
	}
	return
}
@(private)
_arena_alloc :: proc(arena_allocator: ^ArenaAllocator, size: int) -> (ptr: [^]byte) {
	ptr = ptr_add(raw_data(arena_allocator.buffer), arena_allocator.next)

	alignment_offset := align_forward(ptr, 64) // align to 64B, so we can do a faster copy when resizing
	ptr = ptr_add(ptr, alignment_offset)

	arena_allocator.next += size + alignment_offset
	return
}
