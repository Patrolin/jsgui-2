package lib
import "base:intrinsics"
import "core:fmt"

Server :: struct {
	socket:    SocketHandle,
	address:   SocketAddress,
	ioring:    Ioring,
	user_data: rawptr,
	using _:   Server_OsFooter,
}
when ODIN_OS == .Windows {
	ClientAsyncBuffer :: struct {
		async_write_slice: TRANSMIT_FILE_BUFFERS,
		async_rw_slice:    WSABUF,
		async_rw_buffer:   [2048]byte `fmt:"-"`,
	}
} else when ODIN_OS == .Linux {
	ClientAsyncBuffer :: struct {
		async_write_slice: struct{},
		async_rw_slice:    struct{},
		async_rw_buffer:   [2048]byte `fmt:"-"`,
	}
} else {
	//#assert(false)
}
Client :: struct {
	using _:           Client_OsHeader `fmt:"-"`,
	ioring:            Ioring, /* NOTE: pointer to server.ioring */
	socket:            SocketHandle,
	address:           SocketAddress,
	state:             ClientState,
	timeout_timer:     TimerHandle,
	/* `FileHandle` or `INVALID_HANDLE` */
	async_write_file:  FileHandle,
	async_rw_prev_pos: int,
	async_rw_pos:      int,
	using _:           ClientAsyncBuffer `fmt:"-"`,
}
ClientState :: enum {
	New,
	Reading,
	SendingFileResponseAndClosing,
	ClosedByServerResponse,
	ClosedByClient,
	ClosedByTimeout,
	ClosedByServer,
}
when ODIN_OS == .Windows {
	Server_OsFooter :: struct {
		AcceptEx: ACCEPT_EX,
	}
	Client_OsHeader :: struct {
		/* NOTE: OVERLAPPED must be at the top, so you can cast it to ^Client, and must not be moved */
		overlapped: OVERLAPPED `fmt:"-"`,
	}
} else when ODIN_OS == .Linux {
	Server_OsFooter :: struct {}
	Client_OsHeader :: struct {}
} else {
	//#assert(false)
}

// NOTE: call this once per process
init_sockets :: proc() {
	when ODIN_OS == .Windows {
		WINSOCK_MAJOR_VERSION :: 2
		WINSOCK_MINOR_VERSION :: 2
		fmt.assertf(
			WSAStartup(WINSOCK_MAJOR_VERSION | (WINSOCK_MINOR_VERSION << 8), &global_winsock) == 0,
			"Failed to initialize Winsock %v.%v",
			WINSOCK_MAJOR_VERSION,
			WINSOCK_MINOR_VERSION,
		)
	} else when ODIN_OS == .Linux {
		/* noop */
	} else {
		assert(false)
	}
}
create_server_socket :: proc(ioring: Ioring, server: ^Server, port: u16) {
	// create a socket
	when ODIN_OS == .Windows {
		server.socket = WSASocketW(CINT(SocketAddressFamily.AF_INET), .SOCK_STREAM, .PROTOCOL_TCP, nil, .None, {.WSA_FLAG_OVERLAPPED})
		fmt.assertf(server.socket != SocketHandle(INVALID_HANDLE), "Failed to create a server socket")
	} else when ODIN_OS == .Linux {
		server.socket = socket(.AF_INET, .SOCK_STREAM | .SOCK_NONBLOCK, .PROTOCOL_TCP)
		fmt.assertf(server.socket >= 0, "Failed to create a server socket")
		value := CINT(1)
		reuse_err := setsockopt(server.socket, .SOL_SOCKET, .SO_REUSEADDR, &value, size_of(value))
		fmt.assertf(reuse_err == 0, "Failed to set SO_REUSEADDR=1, err: %v", Errno(reuse_err))
	} else {
		assert(false)
	}
	// bind the socket
	server.address = SocketAddressIpv4 {
		family = .AF_INET,
		ip     = u32be(0), // NOTE: 0.0.0.0
		port   = u16be(port),
	}
	bind_err := bind(server.socket, &server.address, size_of(SocketAddressIpv4))
	fmt.assertf(bind_err == 0, "Failed to bind the server socket, err: %v", Errno(bind_err))
	listen_err := listen(server.socket, SOMAXCONN)
	fmt.assertf(listen_err == 0, "Failed to listen to the server socket, err: %v", Errno(listen_err))
	// listen to socket events via ioring
	when ODIN_OS == .Windows {
		fmt.assertf(CreateIoCompletionPort(Handle(server.socket), server.ioring, 0, 0) == server.ioring, "Failed to listen to the server socket via IOCP")
		bytes_written: u32 = 0
		fmt.assertf(
			WSAIoctl(
				server.socket,
				SIO_GET_EXTENSION_FUNCTION_POINTER,
				&WSAID_ACCEPTEX,
				size_of(WSAID_ACCEPTEX),
				&server.AcceptEx,
				size_of(server.AcceptEx),
				&bytes_written,
				nil,
				nil,
			) ==
			0,
			"Failed to setup async accept",
		)
	} else when ODIN_OS == .Linux {
		event := EpollEvent {
			flags = {.EPOLLIN},
			user_data = {rawptr = server},
		}
		epoll_err := epoll_ctl(ioring, .EPOLL_CTL_ADD, Handle(server.socket), &event)
		fmt.assertf(epoll_err == 0, "Failed to listen to the server socket via epoll: %v", Errno(epoll_err))
	} else {
		assert(false)
	}
	fmt.printfln("server: %p, %v", server, server)
	return
}
@(private)
_make_client :: proc(server: ^Server) -> (client: ^Client) {
	client = new(Client) // TODO: how does one allocate a nonzerod struct in Odin?
	client.ioring = server.ioring
	client.async_write_file = FileHandle(INVALID_HANDLE)
	return
}
@(private)
_accept_client_poll :: proc(server: ^Server) -> (client: ^Client) {
	client = _make_client(server)
	when ODIN_OS == .Windows {
		unreachable()
	} else when ODIN_OS == .Linux {
		client.address = SocketAddressIpv4{}
		address_size := CINT(size_of(SocketAddressIpv4))
		client.socket = accept(server.socket, &client.address, &address_size)
		fmt.assertf(client.socket >= 0, "Failed to accept a client socket, err: %v", Errno(client.socket))
	} else {
		assert(false)
	}
	return
}
accept_client_async :: proc(server: ^Server) {
	/* NOTE: on windows we have to allocate ahead of time, on linux we don't */
	when ODIN_OS == .Windows {
		client := _make_client(server)
		client.socket = WSASocketW(CINT(SocketAddressFamily.AF_INET), .SOCK_STREAM, .PROTOCOL_TCP, nil, .None, {.WSA_FLAG_OVERLAPPED})
		fmt.assertf(client.socket != SocketHandle(INVALID_HANDLE), "Failed to reserve a client socket")
		bytes_received: u32 = ---
		//client.overlapped = {} // NOTE: AcceptEx() requires this to be zerod
		ok := server.AcceptEx(
			server.socket,
			client.socket,
			&client.async_rw_buffer[0],
			0,
			size_of(SocketAddressIpv4) + 16,
			size_of(SocketAddressIpv4) + 16,
			&bytes_received,
			&client.overlapped,
		)
		err := GetLastError()
		fmt.assertf(ok == true || err == .ERROR_IO_PENDING, "Failed to accept asynchronously, err: %v", err)
	} else when ODIN_OS == .Linux {
		/* noop */
	} else {
		assert(false)
	}
}
receive_client_data_async :: proc(client: ^Client) {
	intrinsics.atomic_compare_exchange_strong(&client.state, .New, .Reading)
	when ODIN_OS == .Windows {
		client.overlapped = {}
		client.async_rw_slice = {
			buffer = &client.async_rw_buffer[client.async_rw_pos],
			len    = u32(len(client.async_rw_buffer) - client.async_rw_pos),
		}
		flags: u32 = 0 /* TODO: bit_set for this */
		has_error := WSARecv(client.socket, &client.async_rw_slice, 1, nil, &flags, &client.overlapped, nil)
		err := WSAGetLastError()
		fmt.assertf(has_error == 0 || err == .ERROR_IO_PENDING, "Failed to read data asynchronously, %v", err)
	} else when ODIN_OS == .Linux {
		/* noop */
	} else {
		assert(false)
	}
}
/*_send_client_data_async :: proc(client: ^AsyncClient) {
	// TODO: send the response with WSASend(), but then we can't receive data (unless you allocate more overlappeds?)
} */
send_file_response_and_close_client :: proc(client: ^Client, header: []byte, file: FileHandle) {
	// NOTE: don't overwrite if state == .ClosedXX
	old, _ := intrinsics.atomic_compare_exchange_strong(&client.state, .Reading, .SendingFileResponseAndClosing)
	if old == .ClosedByTimeout {return}
	fmt.assertf(old == .Reading, "Cannot send_response_and_close_client() twice on the same client")

	fmt.assertf(len(header) < len(client.async_rw_buffer), "len(header) must be < len(client.async_rw_buffer), got: %v", len(header))
	copy(header, client.async_rw_buffer[:])

	old_file, file_ok := intrinsics.atomic_compare_exchange_strong(&client.async_write_file, FileHandle(INVALID_HANDLE), file)
	fmt.assertf(file_ok, "Failed to set client.async_write_file, was: %v", old_file)

	client.async_rw_prev_pos = 0
	client.async_rw_pos = 0
	client.async_rw_slice = {}
	when ODIN_OS == .Windows {
		client.async_write_slice = {
			head        = &client.async_rw_buffer[0],
			head_length = u32(len(header)),
		}
	} else {
		assert(false)
	}

	when ODIN_OS == .Windows {
		client.overlapped = {}
		ok := TransmitFile(client.socket, client.async_write_file, 0, 0, &client.overlapped, &client.async_write_slice, {.TF_DISCONNECT, .TF_REUSE_SOCKET})
		err := WSAGetLastError()
		fmt.assertf(ok == true || err == .ERROR_IO_PENDING, "Failed to send response, err: %v", err)
	} else {
		assert(false)
	}
}
cancel_timeout :: proc "system" (client: ^Client) {
	ioring_cancel_timer(client.ioring, &client.timeout_timer)
}
close_client :: proc "system" (client: ^Client, loc := #caller_location) {
	cancel_timeout(client)
	when ODIN_OS == .Windows {
		closesocket(client.socket)
	} else when ODIN_OS == .Linux {
		close(FileHandle(client.socket))
	} else {
		assert_contextless(false, loc = loc)
	}
	client.state = .ClosedByServer
}
handle_socket_event :: proc(server: ^Server, event: ^IoringEvent) -> (client: ^Client) {
	if event.user_data == server {
		/* NOTE: on windows we had to allocate ahead of time, on linux we don't */
		client = _accept_client_poll(server)
	} else {
		client = (^Client)(event.user_data)
	}
	switch event.error {
	case .None:
	case .IoCanceled:
		client.state = .ClosedByTimeout
	case .ConnectionClosedByOtherParty:
		client.state = .ClosedByClient
	}

	/* NOTE: iorings are badly designed... */
	TIMEOUT_COMPLETION_KEY :: 1
	TIMEOUT_MS :: 1000
	when ODIN_OS == .Windows {
		if event.completion_key == TIMEOUT_COMPLETION_KEY {
			client.state = .ClosedByTimeout
		}
	} else {
		//assert(false)
	}

	switch client.state {
	case .New:
		// listen to client socket events
		when ODIN_OS == .Windows {
			result := CreateIoCompletionPort(Handle(client.socket), server.ioring, 0, 0)
			fmt.assertf(result != 0, "Failed to listen to the client socket with IOCP")
			err := setsockopt(client.socket, .SOL_SOCKET, .SO_UPDATE_ACCEPT_CONTEXT, &server.socket, size_of(SocketHandle))
			fmt.assertf(err == 0, "Failed to set client params, err: %v", Errno(err))
			/* TODO: get client address on windows */
		} else when ODIN_OS == .Linux {
			epoll_event := EpollEvent {
				flags = {.EPOLLIN, .EPOLLET},
				user_data = {rawptr = client},
			}
			err := epoll_ctl(server.ioring, .EPOLL_CTL_ADD, Handle(client.socket), &epoll_event)
			fmt.assertf(err == 0, "Failed to listen to the client socket via epoll, err: %v", Errno(err))
		} else {
			assert(false)
		}
		// set a timeout
		/* NOTE: IOCP is badly designed, see ioring_set_timer_async() */
		on_timeout :: proc "system" (user_ptr: rawptr, _TimerOrWaitFired: b32) {
			when ODIN_OS == .Windows {
				client := (^Client)(user_ptr)
				PostQueuedCompletionStatus(client.ioring, 0, TIMEOUT_COMPLETION_KEY, &client.overlapped)
			} else {
				assert_contextless(false, "Shouldn't be necessary on other platforms")
			}
		}
	// nocheckin
	//ioring_set_timer_async(server.ioring, &client.timeout_timer, TIMEOUT_MS, client, on_timeout)
	/* TODO: parse address via GetAcceptExSockaddrs()? */
	case .Reading:
		when ODIN_OS == .Windows {
			/* noop */
		} else when ODIN_OS == .Linux {
			buffer := &client.async_rw_buffer
			bytes_read := read(FileHandle(client.socket), &buffer[0], len(buffer))
			if bytes_read >= 0 {
				event.bytes = u32(bytes_read - client.async_rw_pos)
			} else {
				fmt.assertf(Errno(bytes_read) == .EAGAIN || Errno(bytes_read) == .EWOULDBLOCK, "Failed to read from client asynchronously, err: %v", Errno(bytes_read))
			}
			fmt.printfln("-- bytes_read: %v, event.bytes: %v", bytes_read, event.bytes)
		} else {
			assert(false)
		}
		if event.bytes == 0 {
			// NOTE: presumably this means we're out of memory in the async_rw_buffer?
			client.state = .ClosedByClient
		} else {
			client.async_rw_prev_pos = client.async_rw_pos
			client.async_rw_pos += int(event.bytes)
			break
		}
		fallthrough
	case .SendingFileResponseAndClosing:
		client.state = .ClosedByServerResponse
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse:
	case .ClosedByServer:
		assert(false, "Race condition!")
	}
	return
}
