#+private package
package lib

import "base:intrinsics"
import "base:runtime"
import "core:fmt"

/* NOTE: Windows ships only on x64 */

// globals
_winsock: WinsockData

// constants
INVALID_HANDLE :: HANDLE(~uintptr(0))
INFINITE :: max(u32)

WAIT_OBJECT_0: DWORD : 0x000
WAIT_TIMEOUT: DWORD : 0x102
WAIT_FAILED: DWORD : max(u32)

CP_UTF8 :: 65001
WC_ERR_INVALID_CHARS :: 0x80
MB_ERR_INVALID_CHARS :: 0x08

WT_EXECUTEONLYONCE :: 0x8
TF_DISCONNECT :: 0x1
TF_REUSE_SOCKET :: 0x2

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

// types
ULONG_PTR :: uintptr
HANDLE :: distinct rawptr
CSTR :: [^]byte
CWSTR :: [^]u16

BOOL :: b32
BYTE :: u8
WORD :: u16
DWORD :: u32
QWORD :: u64
LARGE_INTEGER :: CLONGLONG

GUID :: struct {
	Data1: DWORD,
	Data2: WORD,
	Data3: WORD,
	Data4: [8]BYTE,
}
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
	hEvent:       HANDLE,
}
OVERLAPPED_COMPLETION_ROUTINE :: proc(
	error_code, bytes_transferred: DWORD,
	lpOverlapped: ^OVERLAPPED,
)
WAITORTIMERCALLBACK :: proc "std" (user_ptr: rawptr, TimerOrWaitFired: BOOL)
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

SECURITY_DESCRIPTOR :: struct {
	/*
	Revision, Sbz1: BYTE,
	Control:        SECURITY_DESCRIPTOR_CONTROL,
	Owner, Group:   PSID,
	Sacl, Dacl:     PACL,
	*/
}
SECURITY_ATTRIBUTES :: struct {
	nLength:              DWORD,
	lpSecurityDescriptor: ^SECURITY_DESCRIPTOR,
	bInheritHandle:       BOOL,
}
THREAD_START_ROUTINE :: proc "system" (param: rawptr) -> DWORD
ThreadId :: distinct DWORD
ThreadHandle :: distinct HANDLE

// Kernel32.lib procs
foreign import kernel32 "system:Kernel32.lib"
@(default_calling_convention = "c")
foreign kernel32 {
	// common procs
	WideCharToMultiByte :: proc(CodePage: CUINT, dwFlags: DWORD, lpWideCharStr: CWSTR, cchWideChar: CINT, lpMultiByteStr: CSTR, cbMultiByte: CINT, lpDefaultChar: CSTR, lpUsedDefaultChar: ^BOOL) -> CINT ---
	MultiByteToWideChar :: proc(CodePage: CUINT, dwFlags: DWORD, lpMultiByteStr: CSTR, cbMultiByte: CINT, lpWideCharStr: CWSTR, cchWideChar: CINT) -> CINT ---
	GetLastError :: proc() -> DWORD ---
	CreateEventW :: proc(attributes: ^SECURITY_ATTRIBUTES, manual_reset: BOOL, initial_state: BOOL, name: CWSTR) -> HANDLE ---
	ResetEvent :: proc(handle: HANDLE) -> BOOL ---
	WaitForSingleObject :: proc(handle: HANDLE, millis: DWORD) -> DWORD ---
	GetOverlappedResult :: proc(handle: HANDLE, overlapped: ^OVERLAPPED, bytes_transferred: ^DWORD, wait: BOOL) -> BOOL ---
	CloseHandle :: proc(handle: HANDLE) -> BOOL ---
	// process procs
	GetCommandLineW :: proc() -> CWSTR ---
	ExitProcess :: proc(uExitCode: CUINT) ---
	// thread procs
	Sleep :: proc(ms: DWORD) ---
	CreateThread :: proc(attributes: ^SECURITY_ATTRIBUTES, stack_size: Size, thread_proc: THREAD_START_ROUTINE, param: rawptr, flags: DWORD, thread_id: ^ThreadId) -> ThreadHandle ---
	// alloc procs
	SetUnhandledExceptionFilter :: proc(filter_callback: TOP_LEVEL_EXCEPTION_FILTER) -> TOP_LEVEL_EXCEPTION_FILTER ---
	VirtualAlloc :: proc(address: rawptr, size: Size, type, protect: DWORD) -> rawptr ---
	VirtualFree :: proc(address: rawptr, size: Size, type: DWORD) -> BOOL ---
	// IOCP procs
	CreateIoCompletionPort :: proc(FileHandle: HANDLE, ExistingCompletionPort: HANDLE, CompletionKey: ULONG_PTR, NumberOfConcurrentThreads: DWORD) -> HANDLE ---
	GetQueuedCompletionStatus :: proc(iocp: HANDLE, bytes_transferred: ^DWORD, user_ptr: ^rawptr, overlapped: ^^OVERLAPPED, millis: DWORD) -> BOOL ---
	CreateTimerQueueTimer :: proc(timer: ^HANDLE, timer_queue: HANDLE, callback: WAITORTIMERCALLBACK, user_ptr: rawptr, timeout_ms, period_ms: DWORD, flags: CULONG) -> BOOL ---
	DeleteTimerQueueTimer :: proc(timer_queue: HANDLE, timer: HANDLE, event: HANDLE) ---
	CancelIoEx :: proc(handle: HANDLE, overlapped: ^OVERLAPPED) -> BOOL ---
}

// helper procs
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
tprint_string_as_wstring :: proc(str: string, allocator := context.temp_allocator) -> []u16 {
	str_len := len(str)
	str_len_cint := CINT(str_len)
	assert(int(str_len_cint) == str_len)

	wlen := MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, raw_data(str), str_len_cint, nil, 0)
	assert(wlen != 0)
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
	assert(written_chars == wlen)
	return cwstr_buf[:cwlen]
}

// path constants
MOVEFILE_REPLACE_EXISTING :: 1

FILE_LIST_DIRECTORY: DWORD : 0x00000001

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

ERROR_PATH_NOT_FOUND :: 3

/* NOTE: *NOT* the max path on windows anymore, but half the apis don't support paths above this... */
MAX_PATH :: 260

// dir types
DirHandle :: distinct HANDLE
FindFile :: distinct HANDLE
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
	cFileName:          [MAX_PATH]u16,
	cAlternateFileName: [14]u16,
	/* Obsolete. Do not use */
	dwFileType:         DWORD,
	/* Obsolete. Do not use */
	dwCreatorType:      DWORD,
	/* Obsolete. Do not use */
	wFinderFlags:       WORD,
}

// file types
FileHandle :: distinct HANDLE
/*
FILETIME :: struct #align (4) {
	value: u64le,
}
*/
FILETIME :: struct {
	dwLowDateTime:  DWORD,
	dwHighDateTime: DWORD,
}

// path procs
@(default_calling_convention = "c")
foreign kernel32 {
	// path procs
	MoveFileExW :: proc(src, dest: CWSTR, flags: DWORD) -> BOOL ---
	// dir procs
	CreateDirectoryW :: proc(path: CWSTR, attributes: ^SECURITY_ATTRIBUTES) -> BOOL ---
	ReadDirectoryChangesW :: proc(dir: DirHandle, buffer: [^]byte, buffer_len: DWORD, subtree: BOOL, filter: DWORD, bytes_returned: ^DWORD, overlapped: ^OVERLAPPED, on_complete: ^OVERLAPPED_COMPLETION_ROUTINE) -> BOOL ---
	FindFirstFileW :: proc(file_name: CWSTR, data: ^WIN32_FIND_DATAW) -> FindFile ---
	FindNextFileW :: proc(find: FindFile, data: ^WIN32_FIND_DATAW) -> BOOL ---
	FindClose :: proc(find: FindFile) -> BOOL ---
	// file procs
	CreateFileW :: proc(lpFileName: CWSTR, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: ^SECURITY_ATTRIBUTES, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: HANDLE) -> HANDLE ---
	GetFileSizeEx :: proc(file: FileHandle, file_size: ^LARGE_INTEGER) -> BOOL ---
	ReadFile :: proc(file: FileHandle, buffer: [^]byte, bytes_to_read: DWORD, bytes_read: ^DWORD, overlapped: ^OVERLAPPED) -> BOOL ---
	WriteFile :: proc(file: FileHandle, buffer: [^]byte, bytes_to_write: DWORD, bytes_written: ^DWORD, overlapped: ^OVERLAPPED) -> BOOL ---
	FlushFileBuffers :: proc(file: FileHandle) -> BOOL ---
}

// socket constants
WSADESCRIPTION_LEN :: 256
WSASYS_STATUS_LEN :: 128
SOMAXCONN :: max(CINT)
INVALID_SOCKET :: max(SOCKET)

SOL_SOCKET :: CINT(max(u16))
SO_UPDATE_ACCEPT_CONTEXT: CINT : 0x700B

ERROR_CONNECTION_ABORTED :: 1236
ERROR_OPERATION_ABORTED :: 995
WSA_IO_INCOMPLETE :: 996
WSA_IO_PENDING :: 997

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

// socket types
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
TRANSMIT_FILE_BUFFERS :: struct {
	head:        [^]byte,
	head_length: DWORD,
	tail:        [^]byte,
	tail_length: DWORD,
}
/* TODO */
Winsock_GROUP :: distinct CUINT
/* TODO */
WSAPROTOCOL_INFOW :: struct {}

// socket imports
/* NOTE: WSAAPI is ignored on 64-bit windows */
foreign import winsock_lib "system:Ws2_32.lib"
@(default_calling_convention = "c")
foreign winsock_lib {
	WSAStartup :: proc(requested_version: WORD, winsock: ^WinsockData) -> CINT ---
	WSAIoctl :: proc(socket: SOCKET, control_code: DWORD, in_buf: rawptr, in_len: DWORD, out_buf: rawptr, out_len: DWORD, bytes_written: ^DWORD, overlapped: ^OVERLAPPED, on_complete: WSAOVERLAPPED_COMPLETION_ROUTINE) -> CINT ---
	WSASocketW :: proc(address_type, connection_type, protocol: CINT, protocol_info: ^WSAPROTOCOL_INFOW, group: Winsock_GROUP, flags: DWORD) -> SOCKET ---
	WSARecv :: proc(socket: SOCKET, buffers: ^WSABUF, buffer_count: DWORD, bytes_received: ^DWORD, flags: ^DWORD, overlapped: ^OVERLAPPED, on_complete: WSAOVERLAPPED_COMPLETION_ROUTINE) -> CINT ---

	socket :: proc(address_type, connection_type, protocol: CINT) -> SOCKET ---
	bind :: proc(socket: SOCKET, address: ^SocketAddress, address_size: CINT) -> CINT ---
	listen :: proc(socket: SOCKET, max_connections: CINT) -> CINT ---
	closesocket :: proc(socket: SOCKET) -> CINT ---
	setsockopt :: proc(socket: SOCKET, level: CINT, optname: CINT, optval: rawptr, optlen: CINT) -> CINT ---

	WSAGetLastError :: proc() -> DWORD ---
}

foreign import winsock_ext_lib "system:Mswsock.lib"
@(default_calling_convention = "c")
foreign winsock_ext_lib {
	TransmitFile :: proc(socket: Socket, file: FileHandle, bytes_to_write, bytes_per_send: DWORD, overlapped: ^OVERLAPPED, transmit_buffers: ^TRANSMIT_FILE_BUFFERS, flags: DWORD) -> BOOL ---
}
