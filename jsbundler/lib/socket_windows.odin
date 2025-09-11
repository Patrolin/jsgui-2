package lib
import "base:intrinsics"
import "core:fmt"
import "core:strings"
import win "core:sys/windows"
import "core:time"

// params
WINSOCK_MAJOR_VERSION :: 2
WINSOCK_MINOR_VERSION :: 2

// constants
WSADESCRIPTION_LEN :: 256
WSASYS_STATUS_LEN :: 128
SOMAXCONN :: max(i32)
INVALID_SOCKET :: max(Socket)
SOCKET_ERROR :: -1
ERROR_CONNECTION_ABORTED :: 1236
ERROR_OPERATION_ABORTED :: 995

ADDRESS_TYPE_IPV4 :: 2
ADDRESS_TYPE_IPV6 :: 23

CONNECTION_TYPE_STREAM :: 1
CONNECTION_TYPE_DGRAM :: 2

PROTOCOL_TCP :: 6
PROTOCOL_UDP :: 17

WT_EXECUTEONLYONCE :: 0x8

// types
WAITORTIMERCALLBACK :: proc "std" (lpParam: win.PVOID, TimerOrWaitFired: win.BOOLEAN)

WinsockData :: struct {
	wVersion:       u16,
	wHighVersion:   u16,
	iMaxSockets:    u16,
	iMaxUdpDg:      u16,
	lpVendorInfo:   ^u8,
	szDescription:  [WSADESCRIPTION_LEN + 1]byte,
	szSystemStatus: [WSASYS_STATUS_LEN + 1]byte,
}

SocketAddress :: union {
	SocketAddressIpv4,
}
SocketAddressIpv4 :: struct {
	family:    u16,
	port:      u16be,
	ip:        u32be,
	_reserved: [8]byte,
}
#assert(size_of(SocketAddressIpv4) == 16)

Socket :: win.SOCKET
Server :: struct {
	socket:   Socket,
	address:  SocketAddress,
	iocp:     win.HANDLE,
	AcceptEx: win.LPFN_ACCEPTEX,
}
AsyncClient :: struct {
	// windows nonsense, NOTE: must be first field of struct
	overlapped:          win.OVERLAPPED `fmt:"-"`,
	address:             SocketAddress,
	socket:              Socket,
	timeout_timer:       win.HANDLE,
	state:               AsyncClientState,
	server:              ^Server,
	// nil if we just accepted the connection
	async_read_prev_pos: int,
	async_read_pos:      int,
	async_read_slice:    win.WSABUF `fmt:"-"`,
	async_read_buffer:   [4096]byte `fmt:"-"`, // TODO: set a better buffer size?
}
AsyncClientState :: enum {
	New,
	Open,
	SendingResponse,
	ClosedByClient,
	ClosedByTimeout,
	ClosedByServer,
}

// globals
@(private)
_winsock: WinsockData

// kernel32.lib imports
foreign import kernel32 "system:Kernel32.lib"
@(default_calling_convention = "c")
foreign winsock_lib {
	CreateTimerQueueTimer :: proc(timer: ^win.HANDLE, timer_queue: win.HANDLE, callback: WAITORTIMERCALLBACK, parameter: win.PVOID, timeout_ms, period_ms: i32, flags: u32) -> win.BOOL ---
	DeleteTimerQueueTimer :: proc(timer_queue: win.HANDLE, timer: win.HANDLE, event: win.HANDLE) ---
	CancelIoEx :: proc(handle: win.HANDLE, lpOverlapped: win.LPOVERLAPPED) -> win.BOOL ---
}

// socket imports
// TODO: wtf calling conventions
foreign import winsock_lib "system:Ws2_32.lib"
@(default_calling_convention = "c")
foreign winsock_lib {
	@(private)
	WSAStartup :: proc(requested_version: u16, winsock: ^WinsockData) -> i32 ---
	@(private)
	WSAIoctl :: proc(s: Socket, dwIoControlCode: u32, lpvInBuffer: rawptr, cbInBuffer: u32, lpvOutBuffer: rawptr, cbOutBuffer: u32, lpcbBytesReturned: ^u32, lpOverlapped: ^win.OVERLAPPED, lpCompletionRoutine: win.LPWSAOVERLAPPED_COMPLETION_ROUTINE) -> i32 ---
}
@(default_calling_convention = "std")
foreign winsock_lib {
	@(private, link_name = "socket")
	winsock_socket :: proc(address_type, connection_type, protocol: i32) -> Socket ---
	@(private, link_name = "bind")
	winsock_bind :: proc(socket: Socket, address: ^SocketAddress, address_size: i32) -> i32 ---
	@(private, link_name = "listen")
	winsock_listen :: proc(socket: Socket, n: i32) -> i32 ---
	@(private, link_name = "accept")
	winsock_accept :: proc(socket: Socket, address: ^SocketAddress, address_size: ^i32) -> Socket ---
	@(private, link_name = "closesocket")
	winsock_closesocket :: proc(socket: Socket) -> i32 ---
	@(private, link_name = "recv")
	winsock_recv :: proc(socket: Socket, buffer: [^]byte, buffer_size, flags: i32) -> i32 ---
	@(private, link_name = "send")
	winsock_send :: proc(socket: Socket, buffer: [^]byte, buffer_size, flags: i32) -> i32 ---
}

// socket procs
@(private)
_u32_from_le :: proc(a, b: u16) -> u16 {
	return a | (b << 8)
}
// NOTE: call this once per process
init_sockets :: proc() {
	fmt.assertf(
		WSAStartup(_u32_from_le(WINSOCK_MAJOR_VERSION, WINSOCK_MINOR_VERSION), &_winsock) == 0,
		"Failed to initialize Winsock %v.%v",
		WINSOCK_MAJOR_VERSION,
		WINSOCK_MINOR_VERSION,
	)
}
create_server_socket :: proc(server: ^Server, port: u16, thread_count := 1) {
	server.address = SocketAddressIpv4 {
		family = ADDRESS_TYPE_IPV4,
		ip     = u32be(0), // NOTE: 0.0.0.0
		port   = u16be(port),
	}
	server.socket = winsock_socket(ADDRESS_TYPE_IPV4, CONNECTION_TYPE_STREAM, PROTOCOL_TCP)
	fmt.assertf(server.socket != INVALID_SOCKET, "Failed to create a server socket")

	fmt.assertf(
		winsock_bind(server.socket, &server.address, size_of(SocketAddressIpv4)) == 0,
		"Failed to bind the server socket",
	)

	fmt.assertf(
		winsock_listen(server.socket, SOMAXCONN) == 0,
		"Failed to listen to the server socket",
	)

	server.iocp = win.CreateIoCompletionPort(win.INVALID_HANDLE_VALUE, nil, 0, 0)
	fmt.assertf(server.iocp != nil, "Failed to create an IOCP port")

	fmt.assertf(
		win.CreateIoCompletionPort(win.HANDLE(server.socket), server.iocp, 0, 0) == server.iocp,
		"Failed to listen to the server socket via IOCP",
	)

	accept_ex_guid := win.WSAID_ACCEPTEX
	bytes_written: u32 = 0
	fmt.assertf(
		WSAIoctl(
			server.socket,
			win.SIO_GET_EXTENSION_FUNCTION_POINTER,
			&accept_ex_guid,
			size_of(accept_ex_guid),
			&server.AcceptEx,
			size_of(server.AcceptEx),
			&bytes_written,
			nil,
			nil,
		) ==
		0,
		"Failed to setup async accept",
	)
	fmt.printfln("bytes_written: %v", bytes_written)
	for i in 0 ..< thread_count {_accept_client_async(server)}
	return
}
@(private)
_accept_client_async :: proc(server: ^Server) {
	client := new(AsyncClient) // TODO: how does one allocate a nonzerod struct in Odin?
	client.socket = win.WSASocketW(
		ADDRESS_TYPE_IPV4,
		CONNECTION_TYPE_STREAM,
		PROTOCOL_TCP,
		nil,
		0,
		win.WSA_FLAG_OVERLAPPED,
	)
	fmt.assertf(client.socket != INVALID_SOCKET, "Failed to create a client socket")
	client.server = server
	//client.overlapped = {} // NOTE: LPFN_ACCEPTEX requires this to be zerod
	bytes_received: u32 = ---
	ok := server.AcceptEx(
		server.socket,
		client.socket,
		&client.async_read_buffer[0],
		0,
		size_of(SocketAddressIpv4) + 16,
		size_of(SocketAddressIpv4) + 16,
		&bytes_received,
		&client.overlapped,
	)
	err := win.GetLastError()
	fmt.assertf(
		ok == true || err == win.ERROR_IO_PENDING,
		"Failed to accept asynchronously, err: %v",
		err,
	)
}
@(private)
_receive_client_data_async :: proc(client: ^AsyncClient) {
	client.overlapped = {} // NOTE: WSARecv() requires this to be zerod
	client.async_read_slice = {
		buf = &client.async_read_buffer[client.async_read_pos],
		len = u32(len(client.async_read_buffer) - client.async_read_pos),
	}
	flags: u32 = 0
	has_error := win.WSARecv(
		client.socket,
		&client.async_read_slice,
		1,
		nil,
		&flags,
		win.LPWSAOVERLAPPED(&client.overlapped),
		nil,
	)
	err := win.WSAGetLastError()
	fmt.assertf(
		has_error == 0 || err == win.WSA_IO_PENDING,
		"Failed to read data asynchronously, %v",
		err,
	)
}
@(private)
_send_client_data_async :: proc(client: ^AsyncClient) {
	// TODO: send the response with WSASend()
}
send_response_and_close_client :: proc(client: ^AsyncClient, response: []byte) {
	old, ok := intrinsics.atomic_compare_exchange_strong(&client.state, .Open, .SendingResponse)
	fmt.assertf(
		old != .SendingResponse,
		"Cannot send_response_and_close_client() twice on the same client",
	)
	if ok {
		// TODO: setup sending response
	}
}
cancel_timeout :: proc "std" (client: ^AsyncClient) {
	DeleteTimerQueueTimer(nil, client.timeout_timer, nil)
}
cancel_io_and_close_client :: proc "std" (client: ^AsyncClient) {
	CancelIoEx(win.HANDLE(client.socket), nil)
	close_client(client)
}
close_client :: proc "std" (client: ^AsyncClient) {
	win.closesocket(client.socket)
	cancel_timeout(client)
	switch client.state {
	case .New, .Open, .SendingResponse:
		client.state = .ClosedByServer
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServer:
	}
}
@(private)
_on_timeout :: proc "std" (lpParam: rawptr, _TimerOrWaitFired: win.BOOLEAN) {
	client := (^AsyncClient)(lpParam)
	if client.state == .Open {
		cancel_io_and_close_client(client) // NOTE: we call CancelIoEx(), which makes windows send a ERROR_OPERATION_ABORTED
	}
}
/* usage:
	for {
		client := wait_for_next_socket_event()
		defer handle_socket_event(client)
		switch client.state {...}
	}
*/
wait_for_next_socket_event :: proc(server: ^Server) -> (client: ^AsyncClient) {
	event_bytes: u32 = ---
	key: uint
	ok := win.GetQueuedCompletionStatus(
		server.iocp,
		&event_bytes,
		&key,
		(^^win.OVERLAPPED)(&client),
		win.INFINITE,
	)
	err := win.GetLastError()
	if !ok {
		switch err {
		case ERROR_CONNECTION_ABORTED:
			client.state = .ClosedByClient
			close_client(client)
		case ERROR_OPERATION_ABORTED:
			client.state = .ClosedByTimeout
		case:
			fmt.assertf(false, "Failed to get next socket event, err: %v", err)
		}
	}

	switch client.state {
	case .New:
		// accept a new connection
		fmt.assertf(
			win.CreateIoCompletionPort(win.HANDLE(client.socket), server.iocp, 0, 0) ==
			server.iocp,
			"Failed to listen to the client socket with IOCP",
		)
		fmt.assertf(
			win.setsockopt(
				client.socket,
				win.SOL_SOCKET,
				win.SO_UPDATE_ACCEPT_CONTEXT,
				rawptr(&server.socket),
				size_of(Socket),
			) ==
			0,
			"Failed to set client params",
		)
		fmt.assertf(
			CreateTimerQueueTimer(
				&client.timeout_timer,
				nil,
				_on_timeout,
				client,
				1000,
				0,
				WT_EXECUTEONLYONCE,
			) ==
			true,
			"Failed to set a timeout",
		)
	// TODO: parse address via GetAcceptExSockaddrs()?
	case .Open:
		fmt.printfln("bytes_received: %v", event_bytes)
		if event_bytes == 0 {
			// NOTE: presumably this means we're out of memory in the async_read_buffer?
			client.state = .ClosedByClient
			cancel_io_and_close_client(client)
		} else {
			client.async_read_prev_pos = client.async_read_pos
			client.async_read_pos += int(event_bytes)
			break
		}
		fallthrough
	case .SendingResponse:
	// TODO
	case .ClosedByClient, .ClosedByTimeout:
	case .ClosedByServer:
		assert(false, "Race condition!")
	}
	//fmt.printfln("%v, client: %p, state: %v", time.now(), client, client.state)
	return
}
handle_socket_event :: proc(server: ^Server, client: ^AsyncClient) {
	switch client.state {
	case .New:
		client.state = .Open
		_receive_client_data_async(client)
		_accept_client_async(server)
	case .Open:
		_receive_client_data_async(client)
	case .SendingResponse:
		_send_client_data_async(client)
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServer:
		client.state = .ClosedByServer
		free(client)
	}
}
