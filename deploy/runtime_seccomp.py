"""Layer ENOSYS denials over Docker's existing seccomp policy.

Old Docker returns EPERM for clone3 and faccessat2, preventing glibc's legacy
thread and file-access fallbacks. Neither syscall is enabled, and the outer
policy remains active. The kernel uses the newest errno when equal-precedence
filters deny the same syscall.
"""
import ctypes
import errno
import os
import platform
import sys


class SockFilter(ctypes.Structure):
    _fields_ = [('code', ctypes.c_ushort), ('jt', ctypes.c_ubyte),
                ('jf', ctypes.c_ubyte), ('k', ctypes.c_uint32)]


class SockFprog(ctypes.Structure):
    _fields_ = [('len', ctypes.c_ushort), ('filter', ctypes.POINTER(SockFilter))]


def filter_instructions(machine, denied_syscalls=(435, 439)):
    arch = {'x86_64': 0xC000003E, 'aarch64': 0xC00000B7}.get(machine)
    if arch is None:
        raise RuntimeError('Unsupported runtime architecture')
    rows = [
        (0x20, 0, 0, 4),           # Load seccomp_data.arch.
        (0x15, 1, 0, arch),        # Only the native 64-bit ABI.
        (0x06, 0, 0, 0),           # Kill a different ABI.
        (0x20, 0, 0, 0),           # Load seccomp_data.nr.
    ]
    for number in denied_syscalls:
        if number not in (435, 439):
            raise RuntimeError('Unsupported runtime syscall restriction')
        rows.extend(((0x15, 0, 1, number), (0x06, 0, 0, 0x00050026)))
    rows.append((0x06, 0, 0, 0x7FFF0000))  # Docker's outer policy still applies.
    return tuple(rows)


def denials_needed(libc):
    # Null clone3 cannot create a task; F_OK on / only checks file existence.
    probes = (
        (435, (ctypes.c_void_p(), 0)),
        (439, (-100, ctypes.c_char_p(b'/'), 0, 0)),
    )
    libc.syscall.restype = ctypes.c_long
    denied = []
    for number, arguments in probes:
        ctypes.set_errno(0)
        result = libc.syscall(number, *arguments)
        error = ctypes.get_errno()
        if result == -1 and error == errno.EPERM:
            denied.append(number)
    return tuple(denied)


def install_filter():
    if sys.platform != 'linux':
        raise RuntimeError('Runtime bootstrap requires Linux')
    machine = platform.machine()
    filter_instructions(machine, ())  # Reject an unknown ABI before probing.
    libc = ctypes.CDLL(None, use_errno=True)
    rows = filter_instructions(machine, denials_needed(libc))
    program = (SockFilter * len(rows))(*(SockFilter(*row) for row in rows))
    descriptor = SockFprog(len(rows), program)
    libc.prctl.argtypes = [ctypes.c_int] + [ctypes.c_ulong] * 4
    libc.prctl.restype = ctypes.c_int
    if libc.prctl(38, 1, 0, 0, 0) != 0:  # PR_SET_NO_NEW_PRIVS.
        raise RuntimeError('Cannot enforce runtime privilege restriction')
    address = ctypes.cast(ctypes.pointer(descriptor), ctypes.c_void_p).value
    if libc.prctl(22, 2, address, 0, 0) != 0:  # PR_SET_SECCOMP / FILTER.
        raise RuntimeError('Cannot install runtime restriction')


def main():
    command = sys.argv[1:]
    if not command:
        print('Runtime command required', file=sys.stderr)
        return 64
    try:
        install_filter()
        os.execvp(command[0], command)
    except (RuntimeError, OSError, ValueError):
        print('Runtime security bootstrap failed', file=sys.stderr)
        return 78


if __name__ == '__main__':
    sys.exit(main())
