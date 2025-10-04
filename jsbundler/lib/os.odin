#+private package
package lib
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:sys/linux"

// common
when ODIN_OS == .Windows {
	/* NOTE: Windows ships only on x64 */
	// types
	BOOL :: b32
	BYTE :: u8
	WORD :: u16
	DWORD :: u32
	QWORD :: u64
	LARGE_INTEGER :: i64

	CSTR :: [^]byte
	CWSTR :: [^]u16
	ULONG_PTR :: uintptr
	Handle :: distinct rawptr

	// flags
	INVALID_HANDLE :: Handle(max(uintptr))
	INFINITE :: max(u32)

	CP_UTF8 :: 65001
	WC_ERR_INVALID_CHARS :: 0x80
	MB_ERR_INVALID_CHARS :: 0x08

	WT_EXECUTEONLYONCE :: 0x8

	/* TODO: can we put these in a bit_set? */
	MEM_COMMIT: DWORD : 0x00001000
	MEM_RESERVE: DWORD : 0x00002000
	MEM_DECOMMIT: DWORD : 0x00004000
	MEM_RELEASE: DWORD : 0x00008000
	PAGE_READWRITE: DWORD : 0x04

	EXCEPTION_MAXIMUM_PARAMETERS :: 15
	STATUS_ACCESS_VIOLATION: DWORD : 0xC0000005
	EXCEPTION_EXECUTE_HANDLER :: 1
	EXCEPTION_CONTINUE_SEARCH :: 0
	EXCEPTION_CONTINUE_EXECUTION :: -1

	ERROR_PATH_NOT_FOUND :: 3
	ERROR_OPERATION_ABORTED :: 995
	ERROR_IO_INCOMPLETE :: 996
	ERROR_IO_PENDING :: 997
	ERROR_CONNECTION_ABORTED :: 1236

	// procs
	foreign import kernel32 "system:Kernel32.lib"
	@(default_calling_convention = "c")
	foreign kernel32 {
		WideCharToMultiByte :: proc(CodePage: CUINT, dwFlags: DWORD, lpWideCharStr: CWSTR, cchWideChar: CINT, lpMultiByteStr: CSTR, cbMultiByte: CINT, lpDefaultChar: CSTR, lpUsedDefaultChar: ^BOOL) -> CINT ---
		MultiByteToWideChar :: proc(CodePage: CUINT, dwFlags: DWORD, lpMultiByteStr: CSTR, cbMultiByte: CINT, lpWideCharStr: CWSTR, cchWideChar: CINT) -> CINT ---
		GetLastError :: proc() -> DWORD ---
		//CreateEventW :: proc(attributes: ^SECURITY_ATTRIBUTES, manual_reset: BOOL, initial_state: BOOL, name: CWSTR) -> HANDLE ---
		//ResetEvent :: proc(handle: HANDLE) -> BOOL ---
		//WaitForSingleObject :: proc(handle: HANDLE, millis: DWORD) -> DWORD ---
		CloseHandle :: proc(handle: Handle) -> BOOL ---
	}

	/* TODO: refactor these */
	@(private = "file")
	tprint_cwstr :: proc(cwstr: CWSTR, wlen := -1, allocator := context.temp_allocator) -> string {
		wlen_cint := CINT(wlen)
		assert(int(wlen_cint) == wlen)

		if intrinsics.expect(wlen_cint == 0, false) {return ""}

		cstr_len := WideCharToMultiByte(
			CP_UTF8,
			WC_ERR_INVALID_CHARS,
			cwstr,
			wlen_cint,
			nil,
			0,
			nil,
			nil,
		)
		/* NOTE: Windows counts the null terminator if wlen == -1 */
		str_len := cstr_len - (wlen == -1 ? 1 : 0)
		if intrinsics.expect(str_len == 0, false) {return ""}

		str_buf, err := make([]byte, cstr_len, allocator = allocator)
		assert(err == nil)
		written_bytes := WideCharToMultiByte(
			CP_UTF8,
			WC_ERR_INVALID_CHARS,
			cwstr,
			wlen_cint,
			&str_buf[0],
			cstr_len,
			nil,
			nil,
		)
		assert(written_bytes == cstr_len)
		return string(str_buf[:str_len])
	}
	@(private = "file")
	tprint_string16 :: proc(wstr: string16, allocator := context.temp_allocator) -> string {
		return tprint_cwstr(raw_data(wstr), len(wstr), allocator = allocator)
	}
	tprint_wstring :: proc {
		tprint_cwstr,
		tprint_string16,
	}
	tprint_string_as_wstring :: proc(
		str: string,
		allocator := context.temp_allocator,
		loc := #caller_location,
	) -> []u16 {
		str_len := len(str)
		str_len_cint := CINT(str_len)
		assert(int(str_len_cint) == str_len, loc = loc)

		wlen := MultiByteToWideChar(
			CP_UTF8,
			MB_ERR_INVALID_CHARS,
			raw_data(str),
			str_len_cint,
			nil,
			0,
		)
		assert(wlen != 0, loc = loc)
		cwlen := wlen + 1
		cwstr_buf := make([]u16, cwlen, allocator = allocator)

		written_chars := MultiByteToWideChar(
			CP_UTF8,
			MB_ERR_INVALID_CHARS,
			raw_data(str),
			str_len_cint,
			&cwstr_buf[0],
			cwlen,
		)
		assert(written_chars == wlen, loc = loc)
		return cwstr_buf[:cwlen]
	}
} else when ODIN_OS == .Linux {
	/* NOTE: linux ships on many architectures, and SYS_XXX probably depends on architecture */
	// types
	Handle :: distinct CUINT

	// flags
	INVALID_HANDLE :: max(Handle)

	ERR_NONE :: int(0)
	ERR_PERM :: int(-1)
	ERR_NOENT :: int(-2)
	ERR_SRCH :: int(-3)
	ERR_INTR :: int(-4)
	ERR_IO :: int(-5)
	ERR_NXIO :: int(-6)
	ERR_2BIG :: int(-7)
	ERR_NOEXEC :: int(-8)
	ERR_BADF :: int(-9)
	ERR_CHILD :: int(-10)
	ERR_AGAIN :: int(-11)
	ERR_WOULDBLOCK :: ERR_AGAIN
	ERR_NOMEM :: int(-12)
	ERR_ACCES :: int(-13)
	ERR_FAULT :: int(-14)
	ERR_NOTBLK :: int(-15)
	ERR_BUSY :: int(-16)
	ERR_EXIST :: int(-17)
	ERR_XDEV :: int(-18)
	ERR_NODEV :: int(-19)
	ERR_NOTDIR :: int(-20)
	ERR_ISDIR :: int(-21)
	ERR_INVAL :: int(-22)
	ERR_NFILE :: int(-23)
	ERR_MFILE :: int(-24)
	ERR_NOTTY :: int(-25)
	ERR_TXTBSY :: int(-26)
	ERR_FBIG :: int(-27)
	ERR_NOSPC :: int(-28)
	ERR_SPIPE :: int(-29)
	ERR_ROFS :: int(-30)
	ERR_MLINK :: int(-31)
	ERR_PIPE :: int(-32)
	ERR_DOM :: int(-33)
	ERR_RANGE :: int(-34)

	ERR_DEADLOCK :: int(-35)
	ERR_NAMETOOLONG :: int(-36)
	ERR_NOLCK :: int(-37)
	ERR_NOSYS :: int(-38)
	ERR_NOTEMPTY :: int(-39)
	ERR_LOOP :: int(-40)
	ERR_UNKNOWN_41 :: int(-41)
	ERR_NOMSG :: int(-42)
	ERR_IDRM :: int(-43)
	ERR_CHRNG :: int(-44)
	ERR_L2NSYNC :: int(-45)
	ERR_L3HLT :: int(-46)
	ERR_L3RST :: int(-47)
	ERR_LNRNG :: int(-48)
	ERR_UNATCH :: int(-49)
	ERR_NOCSI :: int(-50)
	ERR_L2HLT :: int(-51)
	ERR_BADE :: int(-52)
	ERR_BADR :: int(-53)
	ERR_XFULL :: int(-54)
	ERR_NOANO :: int(-55)
	ERR_BADRQC :: int(-56)
	ERR_BADSLT :: int(-57)
	ERR_UNKNOWN_58 :: int(-58)
	ERR_BFONT :: int(-59)
	ERR_NOSTR :: int(-60)
	ERR_NODATA :: int(-61)
	ERR_TIME :: int(-62)
	ERR_NOSR :: int(-63)
	ERR_NONET :: int(-64)
	ERR_NOPKG :: int(-65)
	ERR_REMOTE :: int(-66)
	ERR_NOLINK :: int(-67)
	ERR_ADV :: int(-68)
	ERR_SRMNT :: int(-69)
	ERR_COMM :: int(-70)
	ERR_PROTO :: int(-71)
	ERR_MULTIHOP :: int(-72)
	ERR_DOTDOT :: int(-73)
	ERR_BADMSG :: int(-74)
	ERR_OVERFLOW :: int(-75)
	ERR_NOTUNIQ :: int(-76)
	ERR_BADFD :: int(-77)
	ERR_REMCHG :: int(-78)
	ERR_LIBACC :: int(-79)
	ERR_LIBBAD :: int(-80)
	ERR_LIBSCN :: int(-81)
	ERR_LIBMAX :: int(-82)
	ERR_LIBEXEC :: int(-83)
	ERR_ILSEQ :: int(-84)
	ERR_RESTART :: int(-85)
	ERR_STRPIPE :: int(-86)
	ERR_USERS :: int(-87)
	ERR_NOTSOCK :: int(-88)
	ERR_DESTADDRREQ :: int(-89)
	ERR_MSGSIZE :: int(-90)
	ERR_PROTOTYPE :: int(-91)
	ERR_NOPROTOOPT :: int(-92)
	ERR_PROTONOSUPPORT :: int(-93)
	ERR_SOCKTNOSUPPORT :: int(-94)
	ERR_OPNOTSUPP :: int(-95)
	ERR_PFNOSUPPORT :: int(-96)
	ERR_AFNOSUPPORT :: int(-97)
	ERR_ADDRINUSE :: int(-98)
	ERR_ADDRNOTAVAIL :: int(-99)
	ERR_NETDOWN :: int(-100)
	ERR_NETUNREACH :: int(-101)
	ERR_NETRESET :: int(-102)
	ERR_CONNABORTED :: int(-103)
	ERR_CONNRESET :: int(-104)
	ERR_NOBUFS :: int(-105)
	ERR_ISCONN :: int(-106)
	ERR_NOTCONN :: int(-107)
	ERR_SHUTDOWN :: int(-108)
	ERR_TOOMANYREFS :: int(-109)
	ERR_TIMEDOUT :: int(-110)
	ERR_CONNREFUSED :: int(-111)
	ERR_HOSTDOWN :: int(-112)
	ERR_HOSTUNREACH :: int(-113)
	ERR_ALREADY :: int(-114)
	ERR_INPROGRESS :: int(-115)
	ERR_STALE :: int(-116)
	ERR_UCLEAN :: int(-117)
	ERR_NOTNAM :: int(-118)
	ERR_NAVAIL :: int(-119)
	ERR_ISNAM :: int(-120)
	ERR_REMOTEIO :: int(-121)
	ERR_DQUOT :: int(-122)
	ERR_NOMEDIUM :: int(-123)
	ERR_MEDIUMTYPE :: int(-124)
	ERR_CANCELED :: int(-125)
	ERR_NOKEY :: int(-126)
	ERR_KEYEXPIRED :: int(-127)
	ERR_KEYREVOKED :: int(-128)
	ERR_KEYREJECTED :: int(-129)
	ERR_OWNERDEAD :: int(-130)
	ERR_NOTRECOVERABLE :: int(-131)
	ERR_RFKILL :: int(-132)
	ERR_HWPOISON :: int(-133)

	// procs
	copy_to_cstring :: proc(str: string, cbuffer: []byte) {
		assert(len(str) + 1 < len(cbuffer))
		copy(transmute([]byte)(str), cbuffer)
		cbuffer[len(str)] = 0
	}
} else {
	//#assert(false)
}


// process
when ODIN_OS == .Windows {
	// procs
	foreign kernel32 {
		GetCommandLineW :: proc() -> CWSTR ---
		ExitProcess :: proc(uExitCode: CUINT) ---
	}
} else when ODIN_OS == .Linux {
	// procs
	exit :: #force_inline proc(exit_code: CINT) {
		intrinsics.syscall(linux.SYS_exit, uintptr(exit_code))
	}
} else {
	//#assert(false)
}

// thread
ThreadProc :: proc "system" (param: rawptr) -> u32
when ODIN_OS == .Windows {
	// types
	ThreadId :: distinct DWORD
	ThreadHandle :: distinct Handle

	SECURITY_DESCRIPTOR :: struct {
		/* ... */
	}
	SECURITY_ATTRIBUTES :: struct {
		nLength:              DWORD,
		lpSecurityDescriptor: ^SECURITY_DESCRIPTOR,
		bInheritHandle:       BOOL,
	}
	// procs
	foreign kernel32 {
		Sleep :: proc(ms: DWORD) ---
		CreateThread :: proc(attributes: ^SECURITY_ATTRIBUTES, stack_size: Size, thread_proc: ThreadProc, param: rawptr, flags: DWORD, thread_id: ^ThreadId) -> ThreadHandle ---
	}
} else {
	//#assert(false)
}

// alloc
when ODIN_OS == .Windows {
	// types
	EXCEPTION_RECORD :: struct {
		ExceptionCode:        DWORD,
		ExceptionFlags:       DWORD,
		ExceptionRecord:      ^EXCEPTION_RECORD,
		ExceptionAddress:     rawptr,
		NumberParameters:     DWORD,
		ExceptionInformation: [EXCEPTION_MAXIMUM_PARAMETERS]ULONG_PTR,
	}
	CONTEXT :: struct {
		/* ... */
	}
	_EXCEPTION_POINTERS :: struct {
		ExceptionRecord: ^EXCEPTION_RECORD,
		ContextRecord:   ^CONTEXT,
	}
	TOP_LEVEL_EXCEPTION_FILTER :: proc "std" (exception: ^_EXCEPTION_POINTERS) -> CLONG

	// procs
	foreign kernel32 {
		SetUnhandledExceptionFilter :: proc(filter_callback: TOP_LEVEL_EXCEPTION_FILTER) -> TOP_LEVEL_EXCEPTION_FILTER ---
		VirtualAlloc :: proc(address: rawptr, size: Size, type, protect: DWORD) -> rawptr ---
		VirtualFree :: proc(address: rawptr, size: Size, type: DWORD) -> BOOL ---
	}
} else when ODIN_OS == .Linux {
	// flags
	PROT_NONE :: 0x0
	PROT_EXEC :: 0x1
	PROT_READ :: 0x2
	PROT_WRITE :: 0x4

	MAP_PRIVATE :: 0x02
	MAP_ANONYMOUS :: 0x20

	// procs
	mmap :: #force_inline proc(
		addr: rawptr,
		size: Size,
		prot, flags: CINT,
		file: FileHandle = max(FileHandle),
		offset: uint = 0,
	) -> uintptr {
		return intrinsics.syscall(
			linux.SYS_mmap,
			uintptr(addr),
			uintptr(size),
			uintptr(prot),
			uintptr(flags),
			uintptr(file),
			uintptr(offset),
		)
	}
	munmap :: #force_inline proc(addr: rawptr, size: Size) -> uintptr {
		return intrinsics.syscall(linux.SYS_munmap, uintptr(addr), uintptr(size))
	}
} else {
	//#assert(false)
}

// ioring
when ODIN_OS == .Windows {
	// types
	IocpHandle :: distinct Handle
	OVERLAPPED :: struct {
		Internal:     ^CULONG,
		InternalHigh: ^CULONG,
		using _:      struct #raw_union {
			using _: struct {
				Offset:     DWORD,
				OffsetHigh: DWORD,
			},
			Pointer: rawptr,
		},
		hEvent:       Handle,
	}
	OVERLAPPED_COMPLETION_ROUTINE :: proc(
		error_code, bytes_transferred: DWORD,
		lpOverlapped: ^OVERLAPPED,
	)
	TimerQueueHandle :: distinct Handle
	TimerHandle :: distinct Handle
	WAITORTIMERCALLBACK :: proc "std" (user_ptr: rawptr, TimerOrWaitFired: BOOL)

	// procs
	@(default_calling_convention = "c")
	foreign kernel32 {
		CreateIoCompletionPort :: proc(file: Handle, existing_iocp: IocpHandle, completion_key: ULONG_PTR, max_threads: DWORD) -> IocpHandle ---
		PostQueuedCompletionStatus :: proc(iocp: IocpHandle, bytes_transferred: DWORD, completion_key: ULONG_PTR, overlapped: ^OVERLAPPED) -> BOOL ---
		GetQueuedCompletionStatus :: proc(iocp: IocpHandle, bytes_transferred: ^DWORD, user_ptr: ^rawptr, overlapped: ^^OVERLAPPED, millis: DWORD) -> BOOL ---
		CreateTimerQueueTimer :: proc(timer: ^TimerHandle, timer_queue: TimerQueueHandle, timer_callback: WAITORTIMERCALLBACK, user_ptr: rawptr, timeout_ms, period_ms: DWORD, flags: CULONG) -> BOOL ---
		DeleteTimerQueueTimer :: proc(timer_queue: TimerQueueHandle, timer: TimerHandle, event: Handle) -> BOOL ---
		CancelIoEx :: proc(handle: Handle, overlapped: ^OVERLAPPED) -> BOOL ---
	}
} else {
	//#assert(false)
}

// file
when ODIN_OS == .Windows {
	// types
	DirHandle :: distinct Handle
	FileHandle :: distinct Handle
	FindFile :: distinct Handle

	// flags
	MOVEFILE_REPLACE_EXISTING :: 1

	GENERIC_READ: DWORD : 0x80000000
	GENERIC_WRITE: DWORD : 0x40000000
	GENERIC_EXECUTE: DWORD : 0x20000000
	GENERIC_ALL: DWORD : 0x10000000

	FILE_SHARE_READ: DWORD : 0x00000001
	FILE_SHARE_WRITE: DWORD : 0x00000002
	FILE_SHARE_DELETE: DWORD : 0x00000004

	F_CREATE: DWORD : 1
	F_CREATE_OR_OPEN: DWORD : 4
	F_CREATE_OR_OPEN_AND_TRUNCATE: DWORD : 2
	F_OPEN: DWORD : 3
	F_OPEN_AND_TRUNCATE: DWORD : 5

	FILE_ATTRIBUTE_DIRECTORY: DWORD : 0x00000010
	FILE_ATTRIBUTE_NORMAL: DWORD : 0x00000080

	FILE_FLAG_WRITE_THROUGH: DWORD : 0x80000000
	FILE_FLAG_OVERLAPPED: DWORD : 0x40000000
	FILE_FLAG_NO_BUFFERING: DWORD : 0x20000000
	FILE_FLAG_RANDOM_ACCESS: DWORD : 0x10000000
	FILE_FLAG_SEQUENTIAL_SCAN: DWORD : 0x08000000
	FILE_FLAG_BACKUP_SEMANTICS: DWORD : 0x02000000

	FILE_NOTIFY_CHANGE_FILE_NAME :: 0x00000001
	FILE_NOTIFY_CHANGE_DIR_NAME :: 0x00000002
	FILE_NOTIFY_CHANGE_ATTRIBUTES :: 0x00000004
	FILE_NOTIFY_CHANGE_SIZE :: 0x00000008
	FILE_NOTIFY_CHANGE_LAST_WRITE :: 0x00000010
	FILE_NOTIFY_CHANGE_LAST_ACCESS :: 0x00000020
	FILE_NOTIFY_CHANGE_CREATION :: 0x00000040
	FILE_NOTIFY_CHANGE_SECURITY :: 0x00000100

	// procs
	@(default_calling_convention = "c")
	foreign kernel32 {
		CreateDirectoryW :: proc(path: CWSTR, attributes: ^SECURITY_ATTRIBUTES) -> BOOL ---
		MoveFileExW :: proc(src, dest: CWSTR, flags: DWORD) -> BOOL ---
		FindFirstFileW :: proc(file_name: CWSTR, data: ^WIN32_FIND_DATAW) -> FindFile ---
		FindNextFileW :: proc(find: FindFile, data: ^WIN32_FIND_DATAW) -> BOOL ---
		FindClose :: proc(find: FindFile) -> BOOL ---

		CreateFileW :: proc(lpFileName: CWSTR, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: ^SECURITY_ATTRIBUTES, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: Handle) -> Handle ---
		GetFileSizeEx :: proc(file: FileHandle, file_size: ^LARGE_INTEGER) -> BOOL ---
		ReadFile :: proc(file: FileHandle, buffer: [^]byte, bytes_to_read: DWORD, bytes_read: ^DWORD, overlapped: ^OVERLAPPED) -> BOOL ---
		WriteFile :: proc(file: FileHandle, buffer: [^]byte, bytes_to_write: DWORD, bytes_written: ^DWORD, overlapped: ^OVERLAPPED) -> BOOL ---
		FlushFileBuffers :: proc(file: FileHandle) -> BOOL ---
	}
} else when ODIN_OS == .Linux {
	// types
	DirHandle :: distinct u32
	FileHandle :: distinct u32
	FileMode :: CUINT

	// flags
	AT_FDCWD :: transmute(DirHandle)(i32(-100))
	O_RDONLY :: 0
	O_DIRECTORY :: 0

	// procs
	mkdir :: #force_inline proc(
		dir_path: cstring,
		mode: FileMode = 0o755,
	) -> int #no_bounds_check {
		result := intrinsics.syscall(linux.SYS_mkdir, transmute(uintptr)(dir_path), uintptr(mode))
		return int(result)
	}
	renameat2 :: #force_inline proc(
		src_dir: DirHandle,
		src_path: cstring,
		dest_dir: DirHandle,
		dest_path: cstring,
		flags: CUINT = 0,
	) -> int {
		result := intrinsics.syscall(
			linux.SYS_renameat2,
			uintptr(src_dir),
			transmute(uintptr)(src_path),
			uintptr(dest_dir),
			transmute(uintptr)(dest_path),
			uintptr(flags),
		)
		return int(result)
	}
	open :: #force_inline proc(path: cstring, flags: CINT, mode: FileMode = 0o755) -> uintptr {
		result := intrinsics.syscall(
			linux.SYS_open,
			transmute(uintptr)(path),
			uintptr(flags),
			uintptr(mode),
		)
		return result
	}
} else {
	//#assert(false)
}

// dir
when ODIN_OS == .Windows {
	// types
	FILE_NOTIFY_INFORMATION :: struct {
		next_entry_offset: DWORD,
		action:            DWORD,
		file_name_length:  DWORD,
		file_name:         [1]u16,
	}
	WIN32_FIND_DATAW :: struct {
		dwFileAttributes:   DWORD,
		ftCreationTime:     FILETIME,
		ftLastAccessTime:   FILETIME,
		ftLastWriteTime:    FILETIME,
		nFileSizeHigh:      DWORD,
		nFileSizeLow:       DWORD,
		dwReserved0:        DWORD,
		dwReserved1:        DWORD,
		/* worst api design ever? */
		cFileName:          [WINDOWS_MAX_PATH]u16,
		cAlternateFileName: [14]u16,
		/* Obsolete. Do not use */
		dwFileType:         DWORD,
		/* Obsolete. Do not use */
		dwCreatorType:      DWORD,
		/* Obsolete. Do not use */
		wFinderFlags:       WORD,
	}
	FILETIME :: struct {
		dwLowDateTime:  DWORD,
		dwHighDateTime: DWORD,
	}

	// flags
	FILE_LIST_DIRECTORY: DWORD : 0x00000001

	// procs
	@(default_calling_convention = "c")
	foreign kernel32 {
		ReadDirectoryChangesW :: proc(dir: DirHandle, buffer: [^]byte, buffer_len: DWORD, subtree: BOOL, filter: DWORD, bytes_returned: ^DWORD, overlapped: ^OVERLAPPED, on_complete: ^OVERLAPPED_COMPLETION_ROUTINE) -> BOOL ---
	}
} else when ODIN_OS == .Linux {
	// types
	Dirent64 :: struct {
		inode:      i64,
		_internal:  i64,
		size:       CUSHORT,
		type:       byte,
		cfile_name: [1]byte,
	}

	// procs
	get_directory_entries_64b :: #force_inline proc(
		file: DirHandle,
		buffer: [^]byte,
		buffer_size: int,
	) -> int {
		result := intrinsics.syscall(
			linux.SYS_getdents64,
			uintptr(file),
			uintptr(buffer),
			uintptr(buffer_size),
		)
		return int(result)
	}
} else {
	//#assert(false)
}

// socket
when ODIN_OS == .Windows {
	// globals
	global_winsock: WinsockData

	// types
	GUID :: struct {
		Data1: DWORD,
		Data2: WORD,
		Data3: WORD,
		Data4: [8]BYTE,
	}
	SOCKET :: distinct uintptr
	WSABUF :: struct {
		len:    CULONG,
		buffer: [^]byte,
	}
	WinsockData :: struct {
		wVersion:       u16,
		wHighVersion:   u16,
		iMaxSockets:    u16,
		iMaxUdpDg:      u16,
		lpVendorInfo:   ^u8,
		szDescription:  [WSADESCRIPTION_LEN + 1]byte,
		szSystemStatus: [WSASYS_STATUS_LEN + 1]byte,
	}
	ACCEPT_EX :: proc(
		sListenSocket: SOCKET,
		sAcceptSocket: SOCKET,
		lpOutputBuffer: rawptr,
		dwReceiveDataLength: DWORD,
		dwLocalAddressLength: DWORD,
		dwRemoteAddressLength: DWORD,
		lpdwBytesReceived: ^DWORD,
		lpOverlapped: ^OVERLAPPED,
	) -> BOOL

	WSAOVERLAPPED_COMPLETION_ROUTINE :: proc(
		dwError, cbTransferred: DWORD,
		lpOverlapped: ^OVERLAPPED,
		dwFlags: DWORD,
	)
	WSAPROTOCOL_INFOW :: struct {
		/* ... */
	}

	// flags
	WSADESCRIPTION_LEN :: 256
	WSASYS_STATUS_LEN :: 128
	SOMAXCONN :: max(CINT) /* NOTE: for some reason it's not max(CUINT)... */
	INVALID_SOCKET :: max(SOCKET)

	SOL_SOCKET :: CINT(max(u16)) /* NOTE: CINT used to be 16b... */
	SO_UPDATE_ACCEPT_CONTEXT: CINT : 0x700B

	IOC_OUT :: 0x40000000
	IOC_IN :: 0x80000000
	IOC_WS2 :: 0x08000000
	IOC_INOUT :: IOC_IN | IOC_OUT
	SIO_GET_EXTENSION_FUNCTION_POINTER :: IOC_INOUT | IOC_WS2 | 6

	WSA_FLAG_OVERLAPPED :: 1

	WSAID_ACCEPTEX :: GUID {
		0xb5367df1,
		0xcbac,
		0x11cf,
		{0x95, 0xca, 0x00, 0x80, 0x5f, 0x48, 0xa1, 0x92},
	}
	WSAID_GETACCEPTEXSOCKADDRS :: GUID {
		0xb5367df2,
		0xcbac,
		0x11cf,
		{0x95, 0xca, 0x00, 0x80, 0x5f, 0x48, 0xa1, 0x92},
	}
	WSAID_CONNECTX :: GUID {
		0x25a207b9,
		0xddf3,
		0x4660,
		{0x8e, 0xe9, 0x76, 0xe5, 0x8c, 0x74, 0x06, 0x3e},
	}

	WinsockGroup :: enum CUINT {
		None                   = 0x0,
		SG_UNCONSTRAINED_GROUP = 0x1,
		SG_CONSTRAINED_GROUP   = 0x2,
	}

	// procs
	/* NOTE: WSAAPI is ignored on 64-bit windows */
	foreign import winsock_lib "system:Ws2_32.lib"
	@(default_calling_convention = "c")
	foreign winsock_lib {
		WSAStartup :: proc(requested_version: WORD, winsock: ^WinsockData) -> CINT ---
		WSAIoctl :: proc(socket: SOCKET, control_code: DWORD, in_buf: rawptr, in_len: DWORD, out_buf: rawptr, out_len: DWORD, bytes_written: ^DWORD, overlapped: ^OVERLAPPED, on_complete: WSAOVERLAPPED_COMPLETION_ROUTINE) -> CINT ---
		WSASocketW :: proc(address_type, connection_type, protocol: CINT, protocol_info: ^WSAPROTOCOL_INFOW, group: WinsockGroup, flags: DWORD) -> SOCKET ---
		WSARecv :: proc(socket: SOCKET, buffers: ^WSABUF, buffer_count: DWORD, bytes_received: ^DWORD, flags: ^DWORD, overlapped: ^OVERLAPPED, on_complete: WSAOVERLAPPED_COMPLETION_ROUTINE) -> CINT ---

		socket :: proc(address_type, connection_type, protocol: CINT) -> SOCKET ---
		bind :: proc(socket: SOCKET, address: ^SocketAddress, address_size: CINT) -> CINT ---
		listen :: proc(socket: SOCKET, max_connections: CINT) -> CINT ---
		closesocket :: proc(socket: SOCKET) -> CINT ---
		setsockopt :: proc(socket: SOCKET, level: CINT, optname: CINT, optval: rawptr, optlen: CINT) -> CINT ---

		WSAGetLastError :: proc() -> DWORD ---
	}

	// types
	TRANSMIT_FILE_BUFFERS :: struct {
		head:        [^]byte,
		head_length: DWORD,
		tail:        [^]byte,
		tail_length: DWORD,
	}

	// flags
	TF_DISCONNECT :: 0x1
	TF_REUSE_SOCKET :: 0x2

	// procs
	foreign import winsock_ext_lib "system:Mswsock.lib"
	@(default_calling_convention = "c")
	foreign winsock_ext_lib {
		TransmitFile :: proc(socket: Socket, file: FileHandle, bytes_to_write, bytes_per_send: DWORD, overlapped: ^OVERLAPPED, transmit_buffers: ^TRANSMIT_FILE_BUFFERS, flags: DWORD) -> BOOL ---
	}
} else {
	//#assert(false)
}
