import ast
import unittest
from pathlib import Path


class AsyncBoundaryTests(unittest.TestCase):
    def test_service_status_does_not_publish_fabricated_latency_constants(self):
        source = Path("server.py").read_text(encoding="utf-8")
        self.assertNotIn("self.last_price = 4800.0", source)
        self.assertNotIn('{"XAUUSD": 4800.0}', source)
        self.assertNotIn('"leverage": 500', source)
        self.assertNotIn('"latency": 18', source)
        self.assertNotIn('results["data_latency"] = 12', source)
        self.assertNotIn('results["redis_latency"] = 1', source)

    def test_async_server_paths_do_not_directly_call_sync_firestore_or_llm(self):
        tree = ast.parse(Path("server.py").read_text(encoding="utf-8"))
        blocking_receivers = {
            "db",
            "config_record",
            "doc_ref",
            "old_signals_query",
            "users_ref",
            "trades_today_ref",
            "active_signals_ref",
            "pending_ref",
            "dau_ref",
            "news_col",
            "trade_ref",
            "ai_client",
        }
        blocking_methods = {
            "get",
            "set",
            "update",
            "add",
            "delete",
            "commit",
            "create",
        }
        findings = []

        def root_name(node):
            while isinstance(node, (ast.Attribute, ast.Call)):
                node = node.value if isinstance(node, ast.Attribute) else node.func
            return node.id if isinstance(node, ast.Name) else None

        for function in (
            node for node in ast.walk(tree) if isinstance(node, ast.AsyncFunctionDef)
        ):
            for call in (node for node in ast.walk(function) if isinstance(node, ast.Call)):
                if not isinstance(call.func, ast.Attribute):
                    continue
                if (
                    call.func.attr in blocking_methods
                    and root_name(call.func) in blocking_receivers
                ):
                    findings.append(
                        f"{function.name}:{call.lineno}:{root_name(call.func)}.{call.func.attr}"
                    )
        self.assertEqual(findings, [])


if __name__ == "__main__":
    unittest.main()
