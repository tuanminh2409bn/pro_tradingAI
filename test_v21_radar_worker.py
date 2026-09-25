import unittest
from decimal import Decimal
from pathlib import Path

from radar_worker import (
    BarrierEvidence,
    RadarAssetSnapshot,
    RadarBar,
    RadarConfirmationInvalid,
    RadarModelDecision,
    RadarSourceInvalid,
    RadarWorker,
)


class StubConfirmer:
    def __init__(self, decision_factory):
        self.decision_factory = decision_factory
        self.calls = []

    def confirm(self, *, candidate):
        self.calls.append(candidate)
        return self.decision_factory(candidate)


class InMemoryWorkStore:
    def __init__(self, blocked=()):
        self.blocked = set(blocked)
        self.started = []
        self.completed = []
        self.abandoned = []

    def begin_once(self, *, work_key, ttl_seconds):
        self.started.append((work_key, ttl_seconds))
        return work_key not in self.blocked

    def complete(self, *, work_key, confirmation):
        self.completed.append((work_key, confirmation))

    def abandon(self, *, work_key):
        self.abandoned.append(work_key)


def make_bars(*, symbol, final_volume=Decimal("100")):
    bars = []
    for index in range(21):
        bars.append(
            RadarBar(
                source_bar_id=f"{symbol}-bar-{index}",
                closed_at=1_700_000_000 + index * 300,
                open=Decimal("100"),
                high=Decimal("102"),
                low=Decimal("99"),
                close=Decimal("101"),
                volume=final_volume if index == 20 else Decimal("100"),
            )
        )
    return tuple(bars)


def make_snapshot(index, *, final_volume=Decimal("100"), barrier=None):
    symbol = f"ASSET{index:03d}"
    return RadarAssetSnapshot(
        symbol=symbol,
        timeframe="M5",
        provider="approved-market-provider",
        license_ref="license-2026",
        bars=make_bars(symbol=symbol, final_volume=final_volume),
        barrier=barrier,
    )


def valid_decision(candidate):
    return RadarModelDecision(
        direction="BUY",
        confidence=Decimal("82.5"),
        rationale="Confirmed against the cited closed bars.",
        model="deepseek-chat",
        cited_bar_ids=(candidate.source_bar_ids[-1],),
    )


class RadarWorkerTests(unittest.TestCase):
    def test_legacy_eight_asset_momentum_ai_publisher_is_not_runnable(self):
        server_source = Path("server.py").read_text(encoding="utf-8")
        self.assertNotIn("RADAR_SYMBOLS", server_source)
        self.assertNotIn("async def radar_update_loop", server_source)
        self.assertNotIn("async def _update_radar_prices", server_source)
        self.assertIn("Radar worker unavailable", server_source)

    def test_stage_one_calls_model_only_for_volume_or_barrier_candidates(self):
        snapshots = [make_snapshot(index) for index in range(50)]
        snapshots[0] = make_snapshot(0, final_volume=Decimal("300"))
        snapshots[1] = make_snapshot(
            1,
            barrier=BarrierEvidence(
                kind="structural_resistance",
                source_id="structure-ASSET001-1",
            ),
        )
        confirmer = StubConfirmer(valid_decision)
        store = InMemoryWorkStore()

        result = RadarWorker(confirmer=confirmer, work_store=store).scan(
            watchlist=[snapshot.symbol for snapshot in snapshots],
            snapshots=snapshots,
        )

        self.assertEqual(result.scanned_count, 50)
        self.assertEqual(result.candidate_count, 2)
        self.assertEqual(len(confirmer.calls), 2)
        self.assertEqual(len(result.confirmations), 2)
        self.assertEqual(result.confirmations[0].target.symbol, "ASSET000")
        self.assertEqual(result.confirmations[0].target.timeframe, "M5")
        self.assertEqual(
            result.confirmations[0].target.closed_at,
            snapshots[0].bars[-1].closed_at,
        )
        self.assertIn("volume_3x", confirmer.calls[0].reasons)
        self.assertIn("structural_barrier", confirmer.calls[1].reasons)

    def test_one_hundred_stage_one_rejects_make_zero_model_calls(self):
        snapshots = [make_snapshot(index) for index in range(100)]
        confirmer = StubConfirmer(valid_decision)
        result = RadarWorker(
            confirmer=confirmer, work_store=InMemoryWorkStore()
        ).scan(
            watchlist=[snapshot.symbol for snapshot in snapshots],
            snapshots=snapshots,
        )
        self.assertEqual(result.scanned_count, 100)
        self.assertEqual(result.candidate_count, 0)
        self.assertEqual(confirmer.calls, [])
        self.assertEqual(result.confirmations, ())

    def test_atomic_work_claim_suppresses_duplicate_model_confirmation(self):
        snapshots = [make_snapshot(index) for index in range(50)]
        snapshots[0] = make_snapshot(0, final_volume=Decimal("301"))
        key = f"radar:ASSET000:M5:{snapshots[0].bars[-1].closed_at}"
        confirmer = StubConfirmer(valid_decision)
        result = RadarWorker(
            confirmer=confirmer,
            work_store=InMemoryWorkStore(blocked={key}),
        ).scan(
            watchlist=[snapshot.symbol for snapshot in snapshots],
            snapshots=snapshots,
        )
        self.assertEqual(result.candidate_count, 1)
        self.assertEqual(result.skipped_duplicate_count, 1)
        self.assertEqual(confirmer.calls, [])

    def test_untraceable_model_response_is_rejected_and_work_is_retriable(self):
        snapshots = [make_snapshot(index) for index in range(50)]
        snapshots[0] = make_snapshot(0, final_volume=Decimal("300"))
        store = InMemoryWorkStore()
        confirmer = StubConfirmer(
            lambda candidate: RadarModelDecision(
                direction="BUY",
                confidence=Decimal("99"),
                rationale="Unsupported citation.",
                model="deepseek-chat",
                cited_bar_ids=("unknown-future-bar",),
            )
        )
        with self.assertRaises(RadarConfirmationInvalid):
            RadarWorker(confirmer=confirmer, work_store=store).scan(
                watchlist=[snapshot.symbol for snapshot in snapshots],
                snapshots=snapshots,
            )
        self.assertEqual(len(store.abandoned), 1)
        self.assertEqual(store.completed, [])

    def test_missing_provenance_or_incomplete_watchlist_fails_before_model(self):
        snapshots = [make_snapshot(index) for index in range(50)]
        invalid = list(snapshots)
        invalid[0] = RadarAssetSnapshot(
            symbol="ASSET000",
            timeframe="M5",
            provider="",
            license_ref="license-2026",
            bars=make_bars(symbol="ASSET000"),
        )
        confirmer = StubConfirmer(valid_decision)
        for candidate_snapshots in (invalid, snapshots[:-1]):
            with self.assertRaises(RadarSourceInvalid):
                RadarWorker(
                    confirmer=confirmer, work_store=InMemoryWorkStore()
                ).scan(
                    watchlist=[snapshot.symbol for snapshot in snapshots],
                    snapshots=candidate_snapshots,
                )
        self.assertEqual(confirmer.calls, [])


if __name__ == "__main__":
    unittest.main()
