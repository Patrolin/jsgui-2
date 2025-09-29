package lib

// procs
init_page_fault_handler :: #force_inline proc "contextless" () {
	SetUnhandledExceptionFilter(_page_fault_exception_handler)
}
_page_fault_exception_handler :: proc "std" (exception: ^_EXCEPTION_POINTERS) -> CLONG {
	if exception.ExceptionRecord.ExceptionCode == STATUS_ACCESS_VIOLATION {
		ptr := exception.ExceptionRecord.ExceptionInformation[1]
		page_ptr := rawptr(uintptr(ptr) & ~uintptr(PAGE_SIZE - 1))
		commited_ptr := VirtualAlloc(page_ptr, 4096, MEM_COMMIT, PAGE_READWRITE)
		return(
			page_ptr != nil && commited_ptr != nil ? EXCEPTION_CONTINUE_EXECUTION : EXCEPTION_EXECUTE_HANDLER \
		)
	}
	return EXCEPTION_EXECUTE_HANDLER
}
page_reserve :: proc(size: Size) -> []byte {
	ptr := VirtualAlloc(nil, size, MEM_RESERVE, PAGE_READWRITE)
	assert(ptr != INVALID_HANDLE)
	return ([^]byte)(ptr)[:size]
}
page_free :: proc(ptr: rawptr) {
	assert(bool(VirtualFree(ptr, 0, MEM_RELEASE)))
}
