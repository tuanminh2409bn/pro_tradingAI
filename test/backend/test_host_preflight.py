import unittest
from deploy.check_backend_host import host_issues, probe_command


class HostPreflightTests(unittest.TestCase):
    def test_old_host_and_unconfined_are_rejected(self):
        self.assertTrue(host_issues('Linux', 'ubuntu', '16.04', '4.4.0', '18.09.7', ['name=seccomp,profile=builtin']))
        self.assertEqual(host_issues('Linux', 'ubuntu', '24.04', '6.8.0', '29.8.2', ['name=seccomp,profile=builtin']), [])
        self.assertTrue(host_issues('Linux', 'ubuntu', '24.04', '6.8.0', '29.8.2', ['name=seccomp,profile=unconfined']))
        self.assertTrue(host_issues('Darwin', None, None, '25.0.0', None, None))

    def test_probe_cannot_pull_image_mount_credentials_or_disable_seccomp(self):
        command = probe_command('sha256:' + 'a' * 64)
        for flag in ('--pull=never', '--network=none', '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges:true'):
            self.assertIn(flag, command)
        for flag in ('--privileged', '--volume', '--env-file', '--publish', '--security-opt=seccomp=unconfined'):
            self.assertNotIn(flag, command)
        for value in ('python:latest', 'bad', 'sha256:' + 'a' * 63):
            with self.assertRaises(ValueError): probe_command(value)
