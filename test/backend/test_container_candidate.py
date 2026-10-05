"""Candidate deployment must preserve secrets privately and disable listeners."""

import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from deploy import clone_backend_container as release


class ContainerCandidateTests(unittest.TestCase):
    def test_private_key_replaces_only_the_old_key_without_output(self):
        source = {'Config': {'Env': ['DEEPSEEK_API_KEY=old-test-value', 'KEEP=yes']},
                  'HostConfig': {'NetworkMode': 'host'}}
        calls = []
        def request(method, path, payload=None):
            calls.append((method, path, payload))
            return {'Config': {'Entrypoint': ['python', '/bootstrap.py']}} if method == 'GET' else {'Id': 'new'}
        output = io.StringIO()
        fake_key = 'sk-unit-test-secret-123456789'
        with patch.object(release, 'read_private_deepseek_key', return_value=fake_key), patch.object(release.subprocess, 'check_output', return_value=json.dumps([source]).encode()), patch.object(release, 'docker_request', side_effect=request), patch('sys.argv', ['release', '--source', 'old', '--name', 'new', '--image', 'image', '--port', '8019', '--candidate', '--deepseek-key-file', '/protected/provider-key']), contextlib.redirect_stdout(output):
            release.main()
        payload = next(call[2] for call in calls if call[0] == 'POST' and call[2])
        self.assertEqual([value for value in payload['Env'] if value.startswith('DEEPSEEK_API_KEY=')], ['DEEPSEEK_API_KEY=' + fake_key])
        self.assertIn('KEEP=yes', payload['Env'])
        self.assertNotIn(fake_key, output.getvalue())
        self.assertNotIn('old-test-value', output.getvalue())
        self.assertTrue(json.loads(output.getvalue())['deepseek_key_updated'])

    def test_credential_requires_private_regular_file_and_never_follows_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'provider-key'
            file.write_text('sk-unit-test-secret-123456789\n')
            file.chmod(0o600)
            self.assertEqual(release.read_private_deepseek_key(str(file)), 'sk-unit-test-secret-123456789')
            file.chmod(0o640)
            with self.assertRaises(ValueError):
                release.read_private_deepseek_key(str(file))
            file.chmod(0o600)
            alias = Path(directory) / 'alias'
            alias.symlink_to(file)
            with self.assertRaises(OSError):
                release.read_private_deepseek_key(str(alias))
            file.write_text('x' * 1024)
            with self.assertRaises(ValueError):
                release.read_private_deepseek_key(str(file))

    def test_invalid_key_fails_before_docker_mutation(self):
        with patch.object(release, 'read_private_deepseek_key', side_effect=ValueError('do-not-print-test-secret')), patch.object(release, 'docker_request') as request, patch('sys.argv', ['release', '--source', 'old', '--name', 'new', '--image', 'image', '--port', '8019', '--deepseek-key-file', '/protected/provider-key']), contextlib.redirect_stderr(io.StringIO()) as error:
            with self.assertRaises(SystemExit):
                release.main()
        request.assert_not_called()
        self.assertNotIn('do-not-print-test-secret', error.getvalue())

    def test_candidate_is_loopback_without_workers_and_secret_output(self):
        source = {"Config": {"Env": ["PORT=8000", "PROVIDER_KEY=unit-test-secret"],
                             "Cmd": ["uvicorn", "server:app"]},
                  "HostConfig": {"NetworkMode": "host", "Binds": ["/protected:/app/key:ro"]}}
        requests = []
        def request(method, path, payload=None):
            requests.append((method, path, payload))
            if method == 'GET':
                return {'Config': {'Entrypoint': ['python', '/usr/local/bin/runtime_seccomp.py']}}
            return {"Id": "test-id"} if payload else {}
        output = io.StringIO()
        with patch.object(release.subprocess, "check_output", return_value=json.dumps([source]).encode()), patch.object(release, "docker_request", side_effect=request), patch("sys.argv", ["release", "--source", "old", "--name", "candidate", "--image", "new", "--port", "8011", "--candidate"]), contextlib.redirect_stdout(output):
            release.main()
        payload = next(item[2] for item in requests if item[0] == 'POST' and item[2])
        self.assertEqual(payload['Entrypoint'], ['python', '/usr/local/bin/runtime_seccomp.py'])
        self.assertIn("127.0.0.1", payload["Cmd"])
        self.assertIn("PROTRADING_BACKGROUND_WORKERS=0", payload["Env"])
        self.assertIn("MARKET_HISTORY_PROVIDER=tradingview", payload["Env"])
        self.assertIn("PROVIDER_KEY=unit-test-secret", payload["Env"])
        self.assertEqual(payload["HostConfig"]["Binds"], source["HostConfig"]["Binds"])
        self.assertNotIn("unit-test-secret", output.getvalue())
        self.assertEqual(requests[-1][1], "/containers/test-id/start")
