"""An unavailable provider must not poison the shared closed-candle cache."""

from __future__ import annotations

import ast
import asyncio
import unittest
from pathlib import Path
from types import SimpleNamespace

from market_history import TrustedMtfHistory


class FakeCollection:
    def __init__(self, name, writes):
        self.name = name
        self.writes = writes

    def document(self, name):
        return self

    def where(self, field, operator, value):
        return self

    def update(self, data):
        self.writes.append((self.name, data))

    def get(self):
        return []

    def add(self, data):
        self.writes.append((self.name, data))


def load_handler(writes):
    source = (Path(__file__).parent / 'server.py').read_text(encoding='utf-8')
    node = next(
        node for node in ast.parse(source).body
        if isinstance(node, ast.AsyncFunctionDef) and node.name == 'process_ai_analysis'
    )
    async def noop(*args, **kwargs):
        return None

    def forbidden_cache(*args, **kwargs):
        raise AssertionError('Unavailable history entered shared cache')

    namespace = {
        'Operation': SimpleNamespace(ANALYSIS='analysis'),
        'OperationOutcome': SimpleNamespace(FALLBACK='fallback', SUCCESS='success', FAILURE='failure'),
        'FailureCode': SimpleNamespace(PROVIDER_UNAVAILABLE='provider_unavailable', INTERNAL_ERROR='internal'),
        'operation_recorder': SimpleNamespace(start=lambda op: SimpleNamespace(finish=lambda **kwargs: None)),
        'require_backend_operation': noop,
        'require_daily_loss_capacity': noop,
        'BackendOperation': SimpleNamespace(ANALYSIS='analysis'),
        'normalize_symbol': lambda value: value,
        'db': SimpleNamespace(collection=lambda name: FakeCollection(name, writes)),
        'asyncio': asyncio,
        'os': SimpleNamespace(environ={}),
        'LOCAL_QA_MODE': False,
        'TrustedMtfHistory': TrustedMtfHistory,
        'time': SimpleNamespace(time=lambda: 1_800_000_300),
        'symbol_bound_price': lambda *args: 0.0,
        'build_mtf_feature_pack': lambda **kwargs: {
            'last_closed_candle_timestamp': 1_800_000_000,
            'analysis_available': False,
        },
        'market_analysis_features': lambda data: data,
        'analysis_cache_key': lambda *args: 'analysis:XAUUSD:5:1800000000',
        'analysis_cache': SimpleNamespace(get_or_compute=forbidden_cache),
        'build_unavailable_signal': lambda features: {
            'setup_ready': False, 'veto': False, 'fallback': True,
            'layers': [], 'type': 'NEUTRAL', 'entryPrice': None,
        },
        'strip_user_specific_analysis': lambda data: dict(data),
        'firestore': SimpleNamespace(SERVER_TIMESTAMP='server-time'),
        'is_executable_signal': lambda data: False,
    }
    exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])), 'server.py', 'exec'), namespace)
    return namespace['process_ai_analysis']


class UnavailableAnalysisCacheTests(unittest.IsolatedAsyncioTestCase):
    async def test_unconfigured_provider_emits_unavailable_signal_without_cache_write(self):
        writes = []
        handler = load_handler(writes)
        await handler('request-1', 'XAUUSD', '5', 'alice')
        signals = [data for name, data in writes if name == 'signals']
        self.assertEqual(len(signals), 1)
        self.assertFalse(signals[0]['setup_ready'])
        self.assertFalse(signals[0]['cache_hit'])
        self.assertEqual(signals[0]['userId'], 'alice')
        self.assertEqual(signals[0]['market_source'], 'oanda_practice_tick_volume')


if __name__ == '__main__':
    unittest.main()
