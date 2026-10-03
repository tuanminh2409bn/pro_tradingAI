"""Golden, deterministic coverage for truthful Appendix-8 signal emission."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest

from analysis_contract import (
    legacy_to_analysis_response_v21,
    validate_analysis_response_v21,
)
from feature_engine import build_signal_from_features, build_unavailable_signal


ROOT = Path(__file__).resolve().parents[2]
HEX_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")


def _canonical_digest(value: dict) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _color_values(value):
    if isinstance(value, dict):
        for key, nested in value.items():
            if key == "color" or key.endswith("_color"):
                yield nested
            yield from _color_values(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from _color_values(nested)


class SignalGoldenTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = json.loads(
            (ROOT / "test/fixtures/v21_signal_goldens.json").read_text(
                encoding="utf-8"
            )
        )
        cls.contracts = {
            case["name"]: case["contract"]
            for case in json.loads(
                (ROOT / "test/fixtures/v21_signal_contract_cases.json").read_text(
                    encoding="utf-8"
                )
            )
        }

    def _build(self, case: dict) -> dict:
        builder = (
            build_unavailable_signal
            if case["builder"] == "unavailable"
            else build_signal_from_features
        )
        return legacy_to_analysis_response_v21(builder(case["features"]))

    def test_soft_hard_fallback_bullish_and_bearish_goldens(self):
        self.assertEqual(
            {case["name"] for case in self.cases},
            {
                "soft_bullish",
                "hard_bullish",
                "hard_bearish",
                "fallback_unavailable",
            },
        )
        for case in self.cases:
            with self.subTest(case=case["name"]):
                contract = self._build(case)
                self.assertEqual(contract, self.contracts[case["name"]])
                self.assertEqual(validate_analysis_response_v21(contract), [])
                self.assertEqual(contract["setup_ready"], case["setup_ready"])
                self.assertEqual(contract["veto"], case["veto"])
                execution = contract["layers"]["layer4_execution"]
                if case["direction"] is None:
                    self.assertIsNone(execution)
                else:
                    self.assertEqual(
                        execution["momentum"]["arrow"], case["direction"]
                    )
                self.assertEqual(_canonical_digest(contract), case["sha256"])

    def test_all_emitted_colors_are_hex_and_outputs_are_deterministic(self):
        for case in self.cases:
            with self.subTest(case=case["name"]):
                first = self._build(case)
                second = self._build(case)
                self.assertEqual(first, second)
                colors = list(_color_values(first))
                self.assertTrue(all(HEX_COLOR.fullmatch(color) for color in colors))

    def test_veto_golden_is_non_executable_and_schema_valid(self):
        contract = json.loads(
            (ROOT / "test/fixtures/v21_htf_veto_signal.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(validate_analysis_response_v21(contract), [])
        self.assertTrue(contract["veto"])
        self.assertFalse(contract["setup_ready"])
        self.assertIsNone(contract["layers"]["layer4_execution"])


if __name__ == "__main__":
    unittest.main()
