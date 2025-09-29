package lib
import "base:intrinsics"
import "core:sys/linux"

/* NOTE: linux ships on many architectures */

// constants
PROT_NONE :: 0x0
PROT_EXEC :: 0x1
PROT_READ :: 0x2
PROT_WRITE :: 0x4

MAP_PRIVATE :: 0x02
MAP_ANONYMOUS :: 0x20

// procs
/* TODO: read, write, open, close */
mmap :: #force_inline proc(
	addr: rawptr,
	size: Size,
	prot, flags: CINT,
	file: FileHandle,
	offset: uint,
) {
	return intrinsics.syscall(linux.SYS_mmap, addr, size, prot, flags, file, offset)
}
munmap :: #force_inline proc(addr: rawptr, size: Size) {
	return intrinsics.syscall(linux.SYS_munmap, addr, size)
}
