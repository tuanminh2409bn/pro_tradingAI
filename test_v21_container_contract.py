"""Backend container source-contract regression tests."""

from __future__ import annotations

import ast
import shlex
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def _dockerfile_sources() -> set[str]:
    sources: set[str] = set()
    for raw_line in (ROOT / "Dockerfile").read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line.startswith("COPY "):
            continue
        parts = shlex.split(line)
        if len(parts) >= 3:
            sources.update(parts[1:-1])
    return sources


class BackendContainerContractTests(unittest.TestCase):
    def test_dockerfile_copies_transitive_local_server_imports(self):
        required_sources: set[str] = set()
        pending = ["server.py"]
        while pending:
            source = pending.pop()
            if source in required_sources:
                continue
            required_sources.add(source)
            tree = ast.parse((ROOT / source).read_text(encoding="utf-8"))
            imported_roots: set[str] = set()
            for node in tree.body:
                if isinstance(node, ast.Import):
                    imported_roots.update(alias.name.split(".", 1)[0] for alias in node.names)
                elif isinstance(node, ast.ImportFrom) and node.module:
                    imported_roots.add(node.module.split(".", 1)[0])
            pending.extend(
                f"{module}.py"
                for module in imported_roots
                if (ROOT / f"{module}.py").is_file()
            )
        self.assertEqual(required_sources - _dockerfile_sources(), set())


if __name__ == "__main__":
    unittest.main()
