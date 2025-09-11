package lib
import "core:fmt"
import "core:strings"
import win "core:sys/windows"

// params
WINSOCK_MAJOR_VERSION :: 2
WINSOCK_MINOR_VERSION :: 2

// constants
WSADESCRIPTION_LEN :: 256
WSASYS_STATUS_LEN :: 128
SOMAXCONN :: max(i32)
INVALID_SOCKET :: max(Socket)
SOCKET_ERROR :: -1

ADDRESS_TYPE_IPV4 :: 2
ADDRESS_TYPE_IPV6 :: 23

CONNECTION_TYPE_STREAM :: 1
CONNECTION_TYPE_DGRAM :: 2

PROTOCOL_TCP :: 6
PROTOCOL_UDP :: 17

// socket types
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
	socket:       Socket,
	address:      SocketAddress,
	iocp:         win.HANDLE,
	accept_async: win.LPFN_ACCEPTEX,
}
AsyncClient :: struct {
	// for async reading, NOTE: must be first field of struct
	overlapped:        win.OVERLAPPED,
	address:           SocketAddress,
	socket:            Socket,
	state:             AsyncClientState,
	// nil if we just accepted the connection
	data:              strings.Builder,
	overlapped_pos:    u32,
	overlapped_buffer: [4096]byte, // TODO: set a better buffer size?
}
AsyncClientState :: enum {
	New,
	Open,
	ClosedByClient,
	ClosedByTimeout,
}

// globals
@(private)
_winsock: WinsockData

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
create_server_socket :: proc(port: u16, thread_count := 1) -> (server: Server) {
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
	WSAIoctl(
		server.socket,
		win.SIO_GET_EXTENSION_FUNCTION_POINTER,
		&accept_ex_guid,
		size_of(accept_ex_guid),
		&server.accept_async,
		size_of(server.accept_async),
		&bytes_written,
		nil,
		nil,
	)
	for i in 0 ..< thread_count {accept_client_async(server)}
	return
}
accept_client_async :: proc(server: Server) {
	client := new(AsyncClient) // TODO: how does one allocate a nonzerod struct in Odin?
	client.socket = winsock_socket(ADDRESS_TYPE_IPV4, CONNECTION_TYPE_STREAM, PROTOCOL_TCP)
	//client.overlapped = {} // NOTE: LPFN_ACCEPTEX requires this to be zerod
	bytes_written: u32 = ---
	server.accept_async(
		server.socket,
		client.socket,
		&client.overlapped_buffer[0],
		0,
		size_of(SocketAddressIpv4) + 16,
		size_of(SocketAddressIpv4) + 16,
		&bytes_written,
		&client.overlapped,
	)
}
receive_client_data_async :: proc(client: ^AsyncClient) {
	client.overlapped = {} // NOTE: WSARecv() requires this to be zerod
	wsa_buf := win.WSABUF {
		buf = &client.overlapped_buffer[client.overlapped_pos],
		len = len(client.overlapped_buffer) - client.overlapped_pos,
	}
	flags: u32 = 0
	win.WSARecv(
		client.socket,
		&wsa_buf,
		1,
		nil,
		&flags,
		win.LPWSAOVERLAPPED(&client.overlapped),
		nil,
	)
}
close_client :: proc "c" (client: ^AsyncClient) {
	win.closesocket(client.socket)
	if client.timeout_timer win.CloseHandle(client.timeout_timer);
}
timeout_callback :: proc "c" (lpParam: rawptr, _TimerOrWaitFired: win.BOOLEAN) {
	client := (^AsyncClient)(lpParam)
	win.CancelIo(win.HANDLE(client.socket))
	close_client(client)
	win.PostQueuedCompletionStatus(server.iocp, 0, 0, &client.overlapped)
}
/* usage:
	for {
		client := wait_for_next_socket_event()
		defer handle_socket_event(client)
		switch client.state {...}
	}
*/
wait_for_next_socket_event :: proc(server: Server) -> (client: ^AsyncClient) {
	event_bytes: u32 = ---
	key: uint
	ok := win.GetQueuedCompletionStatus(
		server.iocp,
		&event_bytes,
		&key,
		(^^win.OVERLAPPED)(&client),
		win.INFINITE,
	)

	switch client.state {
	case .New:
		// accept a new connection
		win.setsockopt(
			client.socket,
			win.SOL_SOCKET,
			win.SO_UPDATE_ACCEPT_CONTEXT,
			rawptr(server.socket),
			size_of(Socket),
		)
		win.CreateIoCompletionPort(win.HANDLE(client.socket), server.iocp, 0, 0)
	/*win.CreateTimerQueueTimer(
			client.timeout_timer,
			nil,
			timeout_callback,
			client,
			1,
			0,
			win.WT_EXECUTEONLYONCE,
		)*/
	// TODO: parse address via GetAcceptExSockaddrs()?
	case .Open:
		if event_bytes == 0 {
			client.state = .ClosedByClient
		} else {
			receive_client_data_async(client)
			break
		}
		fallthrough
	case .ClosedByClient:
		close_client(client)
	case .ClosedByTimeout:
		win.CancelIo(win.HANDLE(client.socket))
		close_client(client)
	}
	return
}
handle_socket_event :: proc(server: Server, client: ^AsyncClient) {
	switch client.state {
	case .New:
		client.state = .Open
		receive_client_data_async(client)
		accept_client_async(server)
	case .Open:
	case .ClosedByClient, .ClosedByTimeout:
		free(client)
	}
}
