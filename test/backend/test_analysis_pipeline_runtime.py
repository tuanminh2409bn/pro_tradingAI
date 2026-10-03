"""The deployed pipeline must call three specialists and preserve technical gates."""

import unittest

from analysis_pipeline import run_market_pipeline
from specialist_analysis import SpecialistProviderError


class RuntimePipelineTests(unittest.IsolatedAsyncioTestCase):
    def features(self):
        return {
            'symbol': 'BTCUSD', 'timeframe': '5', 'current_price': 100,
            'last_closed_candle_timestamp': 1700000000, 'atr': 1, 'bias': 'BUY',
            'analysis_available': True, 'history_valid': True,
            'order_blocks': [{'bias': 'bullish', 'top': 101, 'bottom': 99}],
            'confirmation': {'type': 'bullish_engulfing', 'candle_time': 1700000000},
            'htf1': {'history_valid': True, 'order_blocks': []},
            'htf2': {'history_valid': True, 'order_blocks': []},
        }

    async def test_four_calls_have_auditable_unanimous_votes_and_no_user_context(self):
        calls = []
        async def provider(**kwargs):
            calls.append(kwargs)
            agent = kwargs['agent']
            if agent == 'aggregator':
                return {'forecast_text': 'Three measured votes agree.'}
            return {'agent': agent, 'decision': 'BUY', 'confidence': 90,
                    'reason': 'Measured evidence', 'evidence': [agent + ':1700000000']}
        features = {**self.features(), 'userId': 'private-user', 'balance': 777777}
        signal = await run_market_pipeline(features, provider=provider, master_prompt='Use evidence only.',
                                           model='deepseek-flash', correlation_id='market-safe-id')
        self.assertEqual([c['agent'] for c in calls], ['smc', 'vsa', 'macro', 'aggregator'])
        self.assertFalse(signal['fallback'])
        self.assertTrue(signal['setup_ready'])
        self.assertEqual(signal['analysis_audit']['consensus']['agreement_percent'], 100)
        for call in calls:
            self.assertEqual(call['temperature'], 0)
            self.assertIn('Use evidence only.', call['messages'][0]['content'])
            self.assertNotIn('private-user', repr(call))
            self.assertNotIn('777777', repr(call))

    async def test_failed_specialist_skips_aggregator_and_cannot_create_execution(self):
        calls = []
        async def provider(**kwargs):
            calls.append(kwargs['agent'])
            if kwargs['agent'] == 'macro':
                raise SpecialistProviderError('payment_required', 'secret=never-print')
            return {'agent': kwargs['agent'], 'decision': 'BUY', 'confidence': 90,
                    'reason': 'Measured evidence', 'evidence': []}
        signal = await run_market_pipeline(self.features(), provider=provider, master_prompt='Evidence.',
                                           model='deepseek-flash', correlation_id='market-safe-id')
        self.assertEqual(calls, ['smc', 'vsa', 'macro'])
        self.assertTrue(signal['fallback'])
        self.assertFalse(signal['setup_ready'])
        self.assertFalse(any(layer['layer'] == 4 for layer in signal['layers']))
        self.assertNotIn('secret=', repr(signal))

    async def test_aggregator_cannot_override_veto_or_trade_prices(self):
        async def provider(**kwargs):
            if kwargs['agent'] == 'aggregator':
                return {'forecast_text': 'Wait at opposing supply.', 'entryPrice': 999999, 'setup_ready': True}
            return {'agent': kwargs['agent'], 'decision': 'BUY', 'confidence': 90,
                    'reason': 'Measured evidence', 'evidence': []}
        features = self.features()
        features['htf1']['order_blocks'] = [{'bias': 'bearish', 'top': 102, 'bottom': 98}]
        signal = await run_market_pipeline(features, provider=provider, master_prompt='Evidence.',
                                           model='deepseek-flash', correlation_id='market-safe-id')
        self.assertTrue(signal['veto'])
        self.assertFalse(signal['setup_ready'])
        self.assertTrue(signal['fallback'])
        self.assertNotEqual(signal.get('entryPrice'), 999999)
        self.assertFalse(any(layer['layer'] == 4 for layer in signal['layers']))
