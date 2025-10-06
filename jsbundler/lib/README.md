The code here is organized into *mostly* separate files.

Definitions of OS syscalls and constants are in `os.odin`. \
However, `os.odin` can also reference constants and procs found in other \
files, such as with `socket.odin`. This requires cyclic imports, which can \
only be done in Odin if all the files are in the same directory.

Odin also doesn't allow sharing `foreign` statements across different files, \
so we have to put all of the OS specific code in a single file.

All other files use `os.odin` via `when` statements. \
Splitting files into `XXX_windows.odin` and `XXX_linux.odin` only creates \
more confusion, as you end with way too many files that are all organized \
differently, so you can't even compare implementations. \
This way we can also type `XXX()` everywhere, instead of `os.XXX()`.

Having `context.allocator` is actually not good, because you don't really know \
what can allocate and what can't. It's much better to pass the allocator \
explicitly, and have `proc(allocator := context.temp_allocator)` by default.
