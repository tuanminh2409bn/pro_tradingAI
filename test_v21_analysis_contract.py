"""V2.1 Appendix-8 request/response contract fixtures."""

from __future__ import annotations

import json
from pathlib import Path
import unittest

from analysis_contract import (
    legacy_to_analysis_response_v21,
    validate_analysis_request_v21,
    validate_analysis_response_v21,
)
from feature_engine import build_signal_from_features


ROOT = Path(__file__).parent


def _evidence() -> dict:
    return {
        "source": "candle",
        "source_id": "M5:1700000000",
        "timestamp": 1_700_000_000,
    }


def _soft_signal() -> dict:
    return {
        "chart_id": "XAUUSD_M5_1700000000",
        "setup_ready": False,
        "veto": False,
        "veto_data": None,
        "fallback": True,
        "forecast_text": "Waiting for confirmation.",
        "layers": {
            "layer1_structural": [
                {
                    "type": "solid_box",
                    "label": "OB",
                    "color": "#00FF7F",
                    "x": 1_700_000_000,
                    "x_end": 1_700_000_300,
                    "y_top": 100.2,
                    "y_bottom": 99.8,
                    "evidence": _evidence(),
                }
            ],
            "layer2_trap": [],
            "layer3_candle": [],
            "layer4_execution": None,
            "layer5_overlay": [],
        },
    }


def _hard_execution() -> dict:
    return {
        "active": True,
        "entry": 100.0,
        "entry_color": "#0000FF",
        "sl": 99.0,
        "sl_color": "#FF0000",
        "tp": [102.0, 103.0, 104.0],
        "tp_color": "#00FF00",
        "prob": 72.0,
        "momentum": {"arrow": "up", "label": "SIG", "color": "#00FF7F"},
        "curves": [
            {
                "id": "SIG_1",
                "type": "bezier_quadratic",
                "style": "dashed",
                "color": "#00F0FF",
                "points": [
                    {"x": 1_700_000_000, "y": 100.0},
                    {"x": 1_700_000_300, "y": 101.5},
                    {"x": 1_700_000_900, "y": 104.0},
                ],
            },
            {
                "id": "SIG_2",
                "type": "bezier_cubic",
                "style": "dashed",
                "color": "#1E90FF",
                "points": [
                    {"x": 1_700_000_000, "y": 100.0},
                    {"x": 1_700_000_200, "y": 99.7},
                    {"x": 1_700_000_500, "y": 102.0},
                    {"x": 1_700_000_900, "y": 104.0},
                ],
            },
        ],
    }


class AnalysisContractTests(unittest.TestCase):
    def test_shared_htf_veto_fixture_validates_exact_contract(self):
        fixture = json.loads(
            (ROOT / "test/fixtures/v21_htf_veto_signal.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(validate_analysis_response_v21(fixture), [])
        self.assertTrue(fixture["veto"])
        self.assertIsNone(fixture["layers"]["layer4_execution"])

    def test_veto_adapter_normalizes_internal_aliases(self):
        contract = legacy_to_analysis_response_v21(
            {
                "chart_id": "XAUUSD_M5_1700000000",
                "setup_ready": False,
                "veto": True,
                "veto_data": {
                    "reason": "htf_opposing_order_block",
                    "conflict_timeframe": "H4",
                    "danger_zone": {
                        "top": 101.2,
                        "bottom": 99.8,
                        "bias": "bearish",
                    },
                },
                "fallback": False,
                "forecast_text": "Execution frozen.",
                "layers": [],
            }
        )
        self.assertEqual(
            contract["veto_data"],
            {
                "veto_reason": "htf_opposing_order_block",
                "conflict_htf": "H4",
                "danger_zone": {
                    "top": 101.2,
                    "bottom": 99.8,
                    "bias": "bearish",
                },
            },
        )
        self.assertEqual(validate_analysis_response_v21(contract), [])

    def test_json_schema_artifacts_use_exact_appendix_8_layer_key(self):
        request_schema = json.loads((ROOT / "schemas/analysis-request-v2.1.json").read_text())
        response_schema = json.loads((ROOT / "schemas/analysis-response-v2.1.json").read_text())
        self.assertEqual(request_schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertEqual(response_schema["properties"]["layers"]["$ref"], "#/$defs/layers")
        layer_properties = response_schema["$defs"]["layers"]["properties"]
        self.assertIn("layer5_overlay", layer_properties)
        self.assertNotIn("layer5_environment", layer_properties)

    def test_request_requires_the_exact_execution_timeframe_for_each_mode(self):
        valid = (("scalping", "5"), ("day_trading", "15"), ("swing", "60"))
        for mode, timeframe in valid:
            with self.subTest(mode=mode):
                self.assertEqual(
                    validate_analysis_request_v21(
                        {"symbol": "XAUUSD", "trading_mode": mode, "execution_tf": timeframe}
                    ),
                    [],
                )

        errors = validate_analysis_request_v21(
            {
                "symbol": "XAUUSD",
                "trading_mode": "scalping",
                "execution_tf": "15",
                "userId": "attacker",
            }
        )
        self.assertTrue(any("userId" in error for error in errors))
        self.assertTrue(any("execution_tf" in error for error in errors))

    def test_soft_contract_accepts_evidence_but_rejects_any_execution_object(self):
        signal = _soft_signal()
        self.assertEqual(validate_analysis_response_v21(signal), [])
        signal["layers"]["layer4_execution"] = _hard_execution()
        self.assertTrue(any("Soft/Veto" in error for error in validate_analysis_response_v21(signal)))

    def test_hard_contract_requires_exact_colors_and_three_targets(self):
        signal = _soft_signal()
        signal["setup_ready"] = True
        signal["layers"]["layer4_execution"] = _hard_execution()
        self.assertEqual(validate_analysis_response_v21(signal), [])

        signal["layers"]["layer4_execution"]["entry_color"] = "blue"
        self.assertTrue(any("#0000FF" in error for error in validate_analysis_response_v21(signal)))

        signal["layers"]["layer4_execution"] = _hard_execution()
        signal["layers"]["layer4_execution"]["tp"].pop()
        self.assertTrue(any("exactly three" in error for error in validate_analysis_response_v21(signal)))

    def test_feature_builder_converts_to_exact_appendix_8_envelope(self):
        legacy = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "timeframe": "5",
                "bias": "BUY",
                "current_price": 100,
                "atr": 1,
                "last_closed_candle_timestamp": 1_700_000_000,
                "order_blocks": [
                    {
                        "bias": "bullish",
                        "top": 100.2,
                        "bottom": 99.8,
                        "t_start": 1_700_000_000,
                        "t_end": 1_700_000_300,
                    }
                ],
                "setup_ready": False,
                "veto": False,
            }
        )
        contract = legacy_to_analysis_response_v21(legacy)
        self.assertEqual(contract["chart_id"], "XAUUSD_5_1700000000")
        self.assertEqual(
            set(contract),
            {"chart_id", "setup_ready", "veto", "veto_data", "fallback", "forecast_text", "layers"},
        )
        item = contract["layers"]["layer1_structural"][0]
        self.assertEqual(item["type"], "solid_box")
        self.assertEqual(item["x"], 1_700_000_000)
        self.assertEqual(validate_analysis_response_v21(contract), [])

    def test_hard_builder_contract_uses_colors_momentum_and_sig_paths_to_tp3(self):
        legacy = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "timeframe": "5",
                "bias": "BUY",
                "current_price": 100,
                "atr": 1,
                "last_closed_candle_timestamp": 1_700_000_000,
                "touch_zone": {"bias": "bullish", "top": 100.2, "bottom": 99.5},
                "consensus_percent": 100,
                "setup_ready": True,
                "veto": False,
            }
        )
        contract = legacy_to_analysis_response_v21(legacy)
        self.assertEqual(validate_analysis_response_v21(contract), [])
        execution = contract["layers"]["layer4_execution"]
        self.assertEqual(execution["entry_color"], "#0000FF")
        self.assertEqual(execution["sl_color"], "#FF0000")
        self.assertEqual(execution["tp_color"], "#00FF00")
        self.assertIsNone(execution["prob"])
        self.assertEqual(execution["momentum"]["arrow"], "up")
        tp3 = execution["tp"][2]
        self.assertTrue(all(curve["points"][-1]["y"] == tp3 for curve in execution["curves"]))

    def test_analytical_component_without_provenance_is_rejected(self):
        signal = _soft_signal()
        del signal["layers"]["layer1_structural"][0]["evidence"]
        self.assertTrue(any("evidence" in error for error in validate_analysis_response_v21(signal)))

    def test_layer1_line_requires_two_points_and_four_character_label(self):
        signal = _soft_signal()
        signal["layers"]["layer1_structural"] = [
            {
                "type": "dashed_line",
                "label": "CHOCH",
                "color": "#FFD700",
                "x1": 1_700_000_000,
                "y1": 100,
                "evidence": _evidence(),
            }
        ]
        errors = validate_analysis_response_v21(signal)
        self.assertTrue(any("four characters" in error for error in errors))
        self.assertTrue(any("two points" in error for error in errors))

    def test_all_appendix_8_visual_component_shapes_validate_together(self):
        signal = _soft_signal()
        signal["layers"]["layer1_structural"] = [
            {
                "type": "dashed_line", "color": "#FFD700",
                "x1": 1_700_000_000, "y1": 100.0,
                "x2": 1_700_000_300, "y2": 101.0,
                "label": "BOS", "evidence": _evidence(),
            },
            {
                "type": "solid_box", "color": "#BA55D3",
                "x": 1_700_000_000, "x_end": 1_700_000_300,
                "y_top": 101.0, "y_bottom": 100.0,
                "label": "FVG", "evidence": _evidence(),
            },
            {
                "type": "bordered_box", "color": "#F0E68C",
                "x": 1_700_000_000, "x_end": 1_700_000_300,
                "y_top": 99.0, "y_bottom": 98.0,
                "label": "MIT", "evidence": _evidence(),
            },
        ]
        signal["layers"]["layer2_trap"] = [
            {
                "type": "text_tag", "text": "$$$", "color": "#FF0000",
                "x": 1_700_000_000, "y": 101.0, "evidence": _evidence(),
            },
            {
                "type": "text_tag", "text": "LIQ", "color": "#A9A9A9",
                "background_color": "#D3D3D3",
                "x": 1_700_000_000, "y": 99.0, "evidence": _evidence(),
            },
            {
                "type": "arrow", "direction": "down", "label": "TYPE1",
                "color": "#FF0000", "x": 1_700_000_000, "y": 101.0,
                "evidence": _evidence(),
            },
            {
                "type": "volume_tag", "text": "STOP", "color": "#8A2BE2",
                "x": 1_700_000_000, "y": 100.0, "evidence": _evidence(),
            },
        ]
        signal["layers"]["layer3_candle"] = [
            {
                "timestamp": 1_700_000_000, "fill_color": "#8A2BE2",
                "text": "CX", "border": "#FFD700", "divergence": "up",
                "divergence_color": "#00FF7F",
                "evidence": _evidence(),
            },
            {
                "timestamp": 1_700_000_300, "fill_color": "#A9A9A9",
                "text": "ND", "evidence": _evidence(),
            },
        ]
        signal["layers"]["layer5_overlay"] = [
            {
                "type": "ghost_box", "opacity": 0.15, "color": "#FF4500",
                "x": 1_700_000_000, "x_end": 1_700_003_600,
                "y_top": 105.0, "y_bottom": 103.0,
                "tooltip": "H4 supply zone", "evidence": _evidence(),
            },
            {
                "type": "red_zone", "start_time": 1_700_003_600,
                "duration_min": 30, "label": "CPI", "color": "#FF0000",
                "evidence": _evidence(),
            },
            {
                "type": "phase_tracker_text", "label": "PHASE C -> D",
                "color": "#FFFFFF", "evidence": _evidence(),
            },
            {
                "type": "htf_trend", "htf1_label": "M15",
                "htf1_trend": "Bullish", "htf2_label": "H1",
                "htf2_trend": "Bearish", "color": "#FFFFFF",
                "evidence": _evidence(),
            },
        ]

        self.assertEqual(validate_analysis_response_v21(signal), [])


if __name__ == "__main__":
    unittest.main()
