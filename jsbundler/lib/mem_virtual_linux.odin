package lib
import "base:intrinsics"

// procs
page_reserve :: proc(size: Size) -> []byte {
	/* NOTE: linux will auto-commit as needed by default */
	ptr := mmap(nil, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS)
	assert(ptr != max(uintptr))
	return ([^]byte)(ptr)[:size]
}
page_free :: proc(ptr: rawptr) {
	assert(munmap(ptr, 0) == 0)
}
