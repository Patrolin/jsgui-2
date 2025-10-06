package lib

// types
when ODIN_OS == .Windows {
	Handle :: distinct uintptr /* NOTE: linux uses 32 bit handles, so we can't use `nil` in Odin */
} else when ODIN_OS == .Linux {
	Handle :: distinct CUINT
} else {
	//#assert(false)
}
FileHandle :: distinct Handle
DirHandle :: distinct Handle
SocketHandle :: distinct Handle

// flags
INVALID_HANDLE :: max(Handle)
