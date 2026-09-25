import unittest
import ast
from dataclasses import fields
from pathlib import Path

from observability import (
    FailureCode,
    Operation,
    OperationMetric,
    OperationOutcome,
    OperationRecorder,
)


class FakeClock:
    def __init__(self):
        self.value = 10.0

    def __call__(self):
        return self.value


class ObservabilityTests(unittest.TestCase):
    def test_server_instruments_analysis_chat_and_new_execution(self):
        tree = ast.parse(Path("server.py").read_text(encoding="utf-8"))
        functions = {
            node.name: node
            for node in tree.body
            if isinstance(node, ast.AsyncFunctionDef)
        }

        def started_operation(function_name):
            for call in (
                node
                for node in ast.walk(functions[function_name])
                if isinstance(node, ast.Call)
            ):
                if (
                    isinstance(call.func, ast.Attribute)
                    and call.func.attr == "start"
                    and isinstance(call.func.value, ast.Name)
                    and call.func.value.id == "operation_recorder"
                    and call.args
                    and isinstance(call.args[0], ast.Attribute)
                ):
                    return call.args[0].attr
            return None

        self.assertEqual(started_operation("process_ai_analysis"), "ANALYSIS")
        self.assertEqual(started_operation("ai_chat"), "AI_CHAT")
        self.assertEqual(started_operation("execute_trade"), "PAPER_EXECUTION")

    def test_metric_schema_has_no_identity_payload_or_exception_fields(self):
        self.assertEqual(
            {field.name for field in fields(OperationMetric)},
            {"operation", "outcome", "latency_ms", "fallback", "error_code"},
        )

    def test_timer_emits_measured_latency_and_fixed_outcome(self):
        clock = FakeClock()
        emitted = []
        timer = OperationRecorder(sink=emitted.append, clock=clock).start(
            Operation.ANALYSIS
        )
        clock.value = 10.125
        metric = timer.finish(
            outcome=OperationOutcome.SUCCESS,
            fallback=False,
        )
        self.assertEqual(metric.latency_ms, 125)
        self.assertEqual(emitted, [metric])

    def test_failure_uses_allowlisted_code_and_timer_finishes_once(self):
        clock = FakeClock()
        emitted = []
        timer = OperationRecorder(sink=emitted.append, clock=clock).start(
            Operation.PAPER_EXECUTION
        )
        timer.finish(
            outcome=OperationOutcome.FAILURE,
            fallback=False,
            error_code=FailureCode.STORE_UNAVAILABLE,
        )
        with self.assertRaises(RuntimeError):
            timer.finish(
                outcome=OperationOutcome.FAILURE,
                fallback=False,
                error_code=FailureCode.INTERNAL_ERROR,
            )
        self.assertEqual(len(emitted), 1)

    def test_invalid_outcome_error_combinations_fail_closed(self):
        recorder = OperationRecorder(sink=lambda metric: None)
        with self.assertRaises(ValueError):
            recorder.start(Operation.AI_CHAT).finish(
                outcome=OperationOutcome.SUCCESS,
                fallback=False,
                error_code=FailureCode.INTERNAL_ERROR,
            )
        with self.assertRaises(ValueError):
            recorder.start(Operation.AI_CHAT).finish(
                outcome=OperationOutcome.FAILURE,
                fallback=False,
            )
        with self.assertRaises(ValueError):
            recorder.start(Operation.AI_CHAT).finish(
                outcome=OperationOutcome.FALLBACK,
                fallback=False,
            )


if __name__ == "__main__":
    unittest.main()
