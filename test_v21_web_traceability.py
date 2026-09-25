"""Keep every consolidated requirement visible in the acceptance ledger."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parent
REQUIREMENT_ID = re.compile(r"^(?:ARC|M|R|F|J|N|B|C|REF|ROLE|ADM)-\d{2}$")
MATRIX_ID = re.compile(r"(ARC|M|R|F|J|N|B|C|REF|ROLE|ADM)-(\d{2})(?:\.\.(\d{2}))?")
STATUSES = {"NOT_STARTED", "IN_PROGRESS", "BLOCKED", "PASS", "FAIL"}


def _rows(path):
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("|") and not line.startswith("|---"):
            yield [cell.strip() for cell in line.strip("|").split("|")]


class WebTraceabilityTests(unittest.TestCase):
    def test_every_requirement_has_test_browser_target_and_status(self):
        requirements = {
            row[0]
            for row in _rows(ROOT / "tasks/requirements-v2.1.md")
            if REQUIREMENT_ID.fullmatch(row[0])
        }
        self.assertTrue(requirements)

        covered = set()
        for row in _rows(ROOT / "tasks/acceptance-matrix.md"):
            if len(row) != 4:
                continue
            matches = list(MATRIX_ID.finditer(row[0]))
            if not matches:
                continue
            self.assertTrue(row[1], row[0])
            self.assertTrue(row[2], row[0])
            self.assertIn(row[3], STATUSES, row[0])
            for match in matches:
                prefix, first, last = match.groups()
                for number in range(int(first), int(last or first) + 1):
                    covered.add(f"{prefix}-{number:02d}")

        self.assertEqual(requirements - covered, set())


if __name__ == "__main__":
    unittest.main()
