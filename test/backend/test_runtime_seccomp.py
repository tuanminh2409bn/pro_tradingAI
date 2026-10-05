"""Compatibility denies new syscalls, retains Docker filters and fails closed."""
import ctypes
import unittest
from unittest.mock import Mock, patch

from deploy import runtime_seccomp


class RuntimeSeccompTests(unittest.TestCase):
    def test_native_abi_filter_denies_clone3_without_allowing_a_blocked_syscall(self):
        instructions = runtime_seccomp.filter_instructions('x86_64')

        def evaluate(arch, syscall):
            accumulator, position = 0, 0
            while True:
                code, jt, jf, value = instructions[position]
                if code == 0x20:
                    accumulator = {0: syscall, 4: arch}[value]
                elif code == 0x15:
                    position += jt if accumulator == value else jf
                elif code == 0x06:
                    return value
                else:
                    self.fail('Unexpected BPF instruction')
                position += 1

        self.assertEqual(evaluate(0xC000003E, 435), 0x00050000 | 38)
        # apt-key's readable-file check must fall back to legacy faccessat.
        self.assertEqual(evaluate(0xC000003E, 439), 0x00050000 | 38)
        self.assertEqual(evaluate(0xC000003E, 269), 0x7FFF0000)
        self.assertEqual(evaluate(0xC000003E, 56), 0x7FFF0000)
        self.assertEqual(evaluate(0xC000003E, 165), 0x7FFF0000)
        # ALLOW here leaves the outer Docker denial active for mount/clone flags.
        self.assertEqual(evaluate(0x40000003, 435), 0)
        self.assertEqual(ctypes.sizeof(runtime_seccomp.SockFilter), 8)

    def test_install_requires_no_new_privileges_and_seccomp_failures_abort(self):
        libc = Mock()
        libc.prctl.side_effect = [0, -1]
        with patch.object(runtime_seccomp.sys, 'platform', 'linux'), patch.object(runtime_seccomp.platform, 'machine', return_value='x86_64'), patch.object(runtime_seccomp.ctypes, 'CDLL', return_value=libc):
            with self.assertRaises(RuntimeError):
                runtime_seccomp.install_filter()
        self.assertEqual([call.args[0] for call in libc.prctl.call_args_list], [38, 22])

    def test_only_eperm_selects_denial_and_modern_file_checks_remain_available(self):
        for results, errors, expected in (
            ([-1, -1], [1, 1], (435, 439)),
            ([-1, 0], [1, 0], (435,)),
            ([-1, 0], [38, 0], ()),
        ):
            libc = Mock()
            libc.syscall.side_effect = results
            with patch.object(runtime_seccomp.ctypes, 'get_errno', side_effect=errors):
                self.assertEqual(runtime_seccomp.denials_needed(libc), expected)

    def test_unsupported_platform_and_architecture_never_install_a_filter(self):
        with patch.object(runtime_seccomp.sys, 'platform', 'darwin'), patch.object(runtime_seccomp.ctypes, 'CDLL') as load:
            with self.assertRaises(RuntimeError):
                runtime_seccomp.install_filter()
            load.assert_not_called()
        with self.assertRaises(RuntimeError):
            runtime_seccomp.filter_instructions('unknown')
