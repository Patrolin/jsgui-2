package lib
import "base:intrinsics"
import "core:sys/linux"

// constants
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

// helper procs
copy_to_cstring :: proc(str: string, cbuffer: []byte) {
	assert(len(str) + 1 < len(cbuffer))
	copy(transmute([]byte)(str), cbuffer)
	cbuffer[len(str)] = 0
}

/* NOTE: linux ships on many architectures */
// process
exit :: #force_inline proc(exit_code: CINT) {
	intrinsics.syscall(linux.SYS_exit, uintptr(exit_code))
}

// file
AT_FDCWD :: transmute(FileHandle)(int(-100))
O_RDONLY :: 0
O_DIRECTORY :: 0

FileHandle :: distinct uintptr
DirHandle :: distinct uintptr
Dirent64 :: struct {
	inode:      i64,
	_internal:  i64,
	size:       CUSHORT,
	type:       byte,
	cfile_name: [1]byte,
}

FileMode :: CUINT
mkdir :: #force_inline proc(dir_path: cstring, mode: FileMode = 0o755) -> int #no_bounds_check {
	result := intrinsics.syscall(linux.SYS_mkdir, transmute(uintptr)(dir_path), uintptr(mode))
	return int(result)
}
renameat2 :: #force_inline proc(
	src_file: FileHandle,
	src_path: cstring,
	dest_file: FileHandle,
	dest_path: cstring,
	flags: CUINT = 0,
) -> int {
	result := intrinsics.syscall(
		linux.SYS_renameat2,
		uintptr(src_file),
		transmute(uintptr)(src_path),
		uintptr(src_file),
		transmute(uintptr)(src_path),
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
/* get directory entries 64b */
getdents64 :: #force_inline proc(file: DirHandle, buffer: [^]byte, buffer_size: int) -> int {
	result := intrinsics.syscall(
		linux.SYS_getdents64,
		uintptr(file),
		uintptr(buffer),
		uintptr(buffer_size),
	)
	return int(result)
}

// alloc
PROT_NONE :: 0x0
PROT_EXEC :: 0x1
PROT_READ :: 0x2
PROT_WRITE :: 0x4

MAP_PRIVATE :: 0x02
MAP_ANONYMOUS :: 0x20

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
