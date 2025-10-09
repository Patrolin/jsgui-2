package lib

/* NOTE: linux uses 32 bit handles, so we can't use `nil` in Odin */
when ODIN_OS == .Windows {
	Handle :: distinct uintptr
	FileHandle :: distinct Handle
} else when ODIN_OS == .Linux {
	FileHandle :: distinct CINT
	Handle :: FileHandle
} else {
	//#assert(false)
}
DirHandle :: distinct Handle
SocketHandle :: distinct Handle

INVALID_HANDLE :: max(Handle)

// socket
when ODIN_OS == .Windows {
	SocketAddressFamily :: enum u16 {
		Unknown  = 0,
		/* IPv4 */
		AF_INET  = 2,
		/* IPv6 */
		AF_INET6 = 23,
	}
} else when ODIN_OS == .Linux {
	SocketAddressFamily :: enum u16 {
		Unknown  = 0,
		/* IPv4 */
		AF_INET  = 2,
		/* IPv6 */
		AF_INET6 = 10,
	}
} else {
	//#assert(false)
}
SocketConnectionFlags :: enum CINT {
	SOCK_STREAM   = 1,
	SOCK_DGRAM    = 2,
	SOCK_RAW      = 3,
	SOCK_NONBLOCK = 0x0800,
}
/* www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml \
	IPv4 TCP = AF_INET + SOCK_STREAM + PROTOCOL_TCP \
	IPv4 UDP = AF_INET + SOCK_DGRAM + PROTOCOL_UDP \
	IPv4 ICMP = AF_INET + SOCK_RAW + IPPROTO_ICMP
*/
when ODIN_OS == .Windows {
	SocketProtocolType :: enum CINT {
		PROTOCOL_TCP = 6,
		PROTOCOL_UDP = 17,
		SOL_SOCKET   = CINT(max(u16)), /* NOTE: CINT used to be 16b... */
	}
} else when ODIN_OS == .Linux {
	SocketProtocolType :: enum CINT {
		PROTOCOL_TCP = 6,
		PROTOCOL_UDP = 17,
		SOL_SOCKET   = 1,
	}
}
SocketOptionKey :: enum CINT {
	SO_REUSEADDR             = 2,
	/* windows only */
	SO_UPDATE_ACCEPT_CONTEXT = 0x700B,
}

SocketAddress :: union {
	SocketAddressIpv4,
}
SocketAddressIpv4 :: struct {
	family:    SocketAddressFamily,
	port:      u16be,
	ip:        u32be `fmt:"#X"`,
	_reserved: [8]byte,
}
#assert(size_of(SocketAddressIpv4) == 16)
