"""Candidate deployment must preserve secrets privately and disable listeners."""

import contextlib
import io
import json
import unittest
from unittest.mock import patch

from deploy import clone_backend_container as release


class ContainerCandidateTests(unittest.TestCase):
    def test_candidate_is_loopback_without_workers_and_secret_output(self):
        source = {"Config": {"Env": ["PORT=8000", "PROVIDER_KEY=unit-test-secret"],
                             "Cmd": ["uvicorn", "server:app"]},
                  "HostConfig": {"NetworkMode": "host", "Binds": ["/protected:/app/key:ro"]}}
        requests = []
        def request(method, path, payload=None):
            requests.append((method, path, payload))
            return {"Id": "test-id"} if payload else {}
        output = io.StringIO()
        with patch.object(release.subprocess, "check_output", return_value=json.dumps([source]).encode()), patch.object(release, "docker_request", side_effect=request), patch("sys.argv", ["release", "--source", "old", "--name", "candidate", "--image", "new", "--port", "8011", "--candidate"]), contextlib.redirect_stdout(output):
            release.main()
        payload = requests[0][2]
        self.assertIn("127.0.0.1", payload["Cmd"])
        self.assertIn("PROTRADING_BACKGROUND_WORKERS=0", payload["Env"])
        self.assertIn("MARKET_HISTORY_PROVIDER=tradingview", payload["Env"])
        self.assertIn("PROVIDER_KEY=unit-test-secret", payload["Env"])
        self.assertEqual(payload["HostConfig"]["Binds"], source["HostConfig"]["Binds"])
        self.assertNotIn("unit-test-secret", output.getvalue())
        self.assertEqual(requests[-1][1], "/containers/test-id/start")
