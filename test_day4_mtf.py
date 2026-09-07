"""Day 4 — MTF pack, setup_ready / veto gates."""
from __future__ import annotations

import unittest

from feature_engine import (
    aggregate_candles,
    apply_stage_gates,
    build_mtf_feature_pack,
    build_signal_from_features,
    evaluate_setup_and_veto,
    htf_pair_for_execution,
    strip_layer4,
)


def _candles(n=40, start=4400.0, t0=1_700_000_000):
    out = []
    price = start
    for i in range(n):
        o = price
        c = price + (0.4 if i % 2 == 0 else -0.3)
        out.append({"t": t0 + i * 300, "o": o, "h": max(o, c) + 0.5, "l": min(o, c) - 0.5, "c": c})
        price = c
    return out


class TestDay4Mtf(unittest.TestCase):
    def test_htf_pair(self):
        self.assertEqual(htf_pair_for_execution("5"), ("15", "60"))
        self.assertEqual(htf_pair_for_execution("60"), ("240", "1440"))

    def test_aggregate_factor(self):
        c = _candles(30)
        htf = aggregate_candles(c, "5", "15")
        self.assertLess(len(htf), len(c))
        self.assertEqual(htf[0]["t"], c[0]["t"])

    def test_soft_strips_layer4(self):
        candles = _candles()
        # Price far from tiny fabricated zones → typically soft
        pack = build_mtf_feature_pack("XAUUSD", "5", candles, candles[-1]["c"], now_ts=candles[-1]["t"] + 400)
        sig = build_signal_from_features(pack)
        if not sig.get("setup_ready") or sig.get("veto"):
            self.assertTrue(all(int(l.get("layer", -1)) != 4 for l in sig.get("layers", [])))

    def test_apply_stage_gates_strips(self):
        raw = {
            "type": "BUY",
            "layers": [{"layer": 1}, {"layer": 4, "entry_line": {"price": 1}}],
        }
        out = apply_stage_gates(raw, {"setup_ready": False, "veto": False, "veto_data": None})
        self.assertFalse(out["setup_ready"])
        self.assertEqual(strip_layer4(out["layers"]), [{"layer": 1}])
        self.assertTrue(all(int(l.get("layer", -1)) != 4 for l in out["layers"]))

    def test_veto_when_price_in_opposing_htf_ob(self):
        exec_f = {
            "current_price": 100.0,
            "atr": 1.0,
            "bias": "BUY",
            "order_blocks": [{"bias": "bullish", "top": 100.2, "bottom": 99.8}],
            "fvgs": [],
        }
        htf = {
            "timeframe": "60",
            "order_blocks": [{"bias": "bearish", "top": 101.0, "bottom": 99.0}],
        }
        gate = evaluate_setup_and_veto(exec_f, htf, None)
        self.assertTrue(gate["veto"])
        self.assertFalse(gate["setup_ready"])


if __name__ == "__main__":
    unittest.main()
