import asyncio
import unittest
from types import SimpleNamespace

from test.backend.test_v21_unavailable_analysis_cache import load_handler
from market_history import TrustedMtfHistory


class HttpError(Exception):
    def __init__(self, status_code, detail): self.status_code, self.detail = status_code, detail


class AnalysisQuotaBoundaryTests(unittest.IsolatedAsyncioTestCase):
    async def test_exhausted_quota_stops_even_a_cached_analysis(self):
        writes = []
        handler = load_handler(writes)
        globals_ = handler.__globals__
        globals_['HTTPException'] = HttpError
        globals_['os'].environ = {'MARKET_HISTORY_PROVIDER': 'tradingview'}
        globals_['fetch_tradingview_mtf_history'] = lambda **kwargs: asyncio.sleep(0, result=TrustedMtfHistory(True, ''))
        globals_['build_mtf_feature_pack'] = lambda **kwargs: {'last_closed_candle_timestamp': 1800000000, 'analysis_available': True}
        async def deny(owner, request):
            self.assertEqual((owner, request), ('alice', 'quota-request'))
            raise HttpError(429, 'quota_exhausted')
        globals_['consume_analysis_quota'] = deny
        await handler('quota-request', 'BTCUSD', '5', 'alice')
        self.assertFalse(any(name == 'signals' for name, _ in writes))
        self.assertIn(('analysis_requests', {'status': 'ERROR', 'error': 'quota_exhausted'}), writes)
