import unittest
import ast
from pathlib import Path

from admin_controls import (
    AdminAccessDenied,
    AdminConfigurationInvalid,
    BackendOperation,
    KillSwitchActive,
    MasterPromptCache,
    ensure_backend_operation_allowed,
    require_admin,
    validate_admin_watchlist,
)
from entitlements import AccountRole, VerifiedQuotaIdentity


class FakeClock:
    def __init__(self):
        self.value = 0.0

    def __call__(self):
        return self.value


class AdminControlTests(unittest.TestCase):
    def test_only_verified_admin_claim_can_use_admin_controls(self):
        admin = VerifiedQuotaIdentity(
            uid="admin-1", role=AccountRole.STANDARD, is_admin=True
        )
        self.assertIs(require_admin(admin), admin)

        for role in AccountRole:
            with self.assertRaises(AdminAccessDenied):
                require_admin(VerifiedQuotaIdentity(uid=role.value, role=role))

        with self.assertRaises(AdminAccessDenied):
            require_admin(
                VerifiedQuotaIdentity(
                    uid="reserved-admin", role=AccountRole.RESERVED_FIFTH,
                    is_admin=True,
                )
            )

    def test_master_prompt_cache_expires_at_exactly_five_minutes(self):
        clock = FakeClock()
        prompts = ["A" * 60, "B" * 60]
        calls = []

        def load_prompt():
            calls.append(True)
            return prompts.pop(0)

        cache = MasterPromptCache(loader=load_prompt, clock=clock)
        self.assertEqual(cache.get(), "A" * 60)
        clock.value = 299.999
        self.assertEqual(cache.get(), "A" * 60)
        self.assertEqual(len(calls), 1)

        clock.value = 300.0
        self.assertEqual(cache.get(), "B" * 60)
        self.assertEqual(len(calls), 2)

    def test_prompt_invalidation_refreshes_without_rebuild_and_invalid_fails_closed(self):
        clock = FakeClock()
        current = {"prompt": "A" * 60}
        cache = MasterPromptCache(
            loader=lambda: current["prompt"], clock=clock
        )
        self.assertEqual(cache.get(), "A" * 60)
        current["prompt"] = "B" * 60
        self.assertEqual(cache.get(), "A" * 60)
        cache.invalidate()
        self.assertEqual(cache.get(), "B" * 60)

        current["prompt"] = "short"
        clock.value = 300.0
        with self.assertRaises(AdminConfigurationInvalid):
            cache.get()

    def test_kill_switch_blocks_both_analysis_and_execution(self):
        for operation in BackendOperation:
            ensure_backend_operation_allowed(
                trading_enabled=True, operation=operation
            )
            with self.assertRaises(KillSwitchActive):
                ensure_backend_operation_allowed(
                    trading_enabled=False, operation=operation
                )
        with self.assertRaises(AdminConfigurationInvalid):
            ensure_backend_operation_allowed(
                trading_enabled=None, operation=BackendOperation.ANALYSIS
            )

    def test_watchlist_requires_50_to_100_unique_valid_assets(self):
        valid = [f"ASSET{i:03d}" for i in range(50)]
        self.assertEqual(validate_admin_watchlist(valid), tuple(valid))
        self.assertEqual(
            len(validate_admin_watchlist([f"ASSET{i:03d}" for i in range(100)])),
            100,
        )
        for invalid in (
            valid[:49],
            [f"ASSET{i:03d}" for i in range(101)],
            valid[:-1] + [valid[0]],
            valid[:-1] + ["bad symbol!"],
        ):
            with self.assertRaises(AdminConfigurationInvalid):
                validate_admin_watchlist(invalid)

    def test_server_gates_new_analysis_and_execution_but_not_trade_close(self):
        tree = ast.parse(Path("server.py").read_text(encoding="utf-8"))
        functions = {
            node.name: node
            for node in tree.body
            if isinstance(node, ast.AsyncFunctionDef)
        }

        def gated_operation(function_name):
            for node in ast.walk(functions[function_name]):
                if not isinstance(node, ast.Call):
                    continue
                if (
                    isinstance(node.func, ast.Name)
                    and node.func.id == "require_backend_operation"
                    and node.args
                    and isinstance(node.args[0], ast.Attribute)
                ):
                    return node.args[0].attr
            return None

        self.assertEqual(gated_operation("process_ai_analysis"), "ANALYSIS")
        self.assertEqual(gated_operation("ai_chat"), "ANALYSIS")
        self.assertEqual(gated_operation("execute_trade"), "EXECUTION")
        self.assertIsNone(gated_operation("close_trade"))


if __name__ == "__main__":
    unittest.main()
