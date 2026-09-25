"""Adversarial paper-execution contract checks, without Firebase or network."""

import unittest

from trade_gate import (
    AuthDenied,
    TradeDenied,
    trade_document_id,
    validate_trade_intent,
    verify_user_identity,
)


NOW = 1_800_000_300


def hard_signal():
    return {
        "userId": "alice",
        "status": "ACTIVE",
        "chart_id": "XAUUSD_5_1800000000",
        "symbol": "XAUUSD",
        "market_source": "oanda_practice_tick_volume",
        "market_closed_at": 1_800_000_000,
        "type": "BUY",
        "setup_ready": True,
        "veto": False,
        "entryPrice": 2400.0,
        "slPrice": 2390.0,
        "tpPrices": [2420.0, 2430.0, 2440.0],
        "layers": [{"layer": 4}],
    }


def intent():
    return {
        "signalChartId": "XAUUSD_5_1800000000",
        "symbol": "XAUUSD",
        "action": "BUY",
        "volume": 0.1,
        "entryPrice": 2400.0,
        "slPrice": 2390.0,
        "tpPrices": [2420.0],
        "tradingMode": "scalping",
    }


class TradeGateTests(unittest.TestCase):
    def test_current_hard_signal_allows_one_allocated_tp_leg(self):
        self.assertEqual(
            validate_trade_intent("alice", intent(), hard_signal(), now=NOW),
            "XAUUSD",
        )

    def test_cross_user_and_stale_signal_are_denied(self):
        for uid, signal in [
            ("bob", hard_signal()),
            ("alice", {**hard_signal(), "status": "CLOSED"}),
            ("alice", {**hard_signal(), "chart_id": "XAUUSD_5_1799990000"}),
        ]:
            with self.subTest(uid=uid, signal=signal["status"]):
                with self.assertRaises(TradeDenied):
                    validate_trade_intent(uid, intent(), signal, now=NOW)

    def test_soft_veto_and_no_execution_layer_are_denied(self):
        for change in [
            {"setup_ready": False},
            {"veto": True},
            {"layers": []},
        ]:
            with self.subTest(change=change):
                with self.assertRaises(TradeDenied):
                    validate_trade_intent(
                        "alice", intent(), {**hard_signal(), **change}, now=NOW
                    )

    def test_paper_execution_requires_trusted_history_provenance(self):
        for change in [
            {"market_source": "server_market_stream"},
            {"market_source": None},
            {"market_closed_at": 1_799_999_700},
        ]:
            with self.subTest(change=change), self.assertRaises(TradeDenied):
                validate_trade_intent(
                    "alice", intent(), {**hard_signal(), **change}, now=NOW
                )

    def test_tampered_prices_direction_target_and_size_are_denied(self):
        for change in [
            {"action": "SELL"},
            {"entryPrice": 2401.0},
            {"slPrice": 2395.0},
            {"tpPrices": [2450.0]},
            {"volume": float("nan")},
            {"volume": 0.0},
            {"tradingMode": "swing"},
        ]:
            with self.subTest(change=change):
                with self.assertRaises(TradeDenied):
                    validate_trade_intent(
                        "alice", {**intent(), **change}, hard_signal(), now=NOW
                    )

    def test_idempotency_doc_id_is_stable_per_owner_and_intent(self):
        first = trade_document_id("alice", "intent-000000001")
        self.assertEqual(first, trade_document_id("alice", "intent-000000001"))
        self.assertNotEqual(first, trade_document_id("alice", "intent-000000002"))
        self.assertNotEqual(first, trade_document_id("bob", "intent-000000001"))
        with self.assertRaises(TradeDenied):
            trade_document_id("alice", "invalid/key")


class TradeAuthTests(unittest.IsolatedAsyncioTestCase):
    async def test_broker_link_requires_verified_partner_role(self):
        for role, allowed in [
            (None, False),
            ("standard", False),
            ("professional", False),
            ("enterprise", False),
            ("reserved_fifth", False),
            ("verified_partner", True),
        ]:
            with self.subTest(role=role):
                claims = {"uid": "alice"}
                if role is not None:
                    claims["role"] = role
                if allowed:
                    self.assertEqual(
                        await verify_user_identity(
                            "Bearer valid", "alice", lambda token: claims,
                            invalid_errors=(ValueError,),
                            required_role="verified_partner",
                        ),
                        "alice",
                    )
                else:
                    with self.assertRaises(AuthDenied) as error:
                        await verify_user_identity(
                            "Bearer valid", "alice", lambda token: claims,
                            invalid_errors=(ValueError,),
                            required_role="verified_partner",
                        )
                    self.assertEqual(error.exception.status_code, 403)

    async def test_missing_invalid_and_cross_user_tokens_fail(self):
        def verify(token):
            if token == "expired":
                raise ValueError("expired")
            return {"uid": "alice"}

        for header, claimed, status in [
            (None, "", 401),
            ("Bearer expired", "", 401),
            ("Bearer valid", "bob", 403),
        ]:
            with self.subTest(header=header, claimed=claimed):
                with self.assertRaises(AuthDenied) as error:
                    await verify_user_identity(
                        header, claimed, verify, invalid_errors=(ValueError,)
                    )
                self.assertEqual(error.exception.status_code, status)

    async def test_verified_uid_not_client_claim_controls_owner(self):
        uid = await verify_user_identity(
            "Bearer valid", "alice", lambda token: {"uid": "alice"},
            invalid_errors=(ValueError,),
        )
        self.assertEqual(uid, "alice")


if __name__ == "__main__":
    unittest.main()
