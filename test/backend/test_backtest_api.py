import ast
import asyncio
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from backtest_api import backtest_creation, same_backtest_creation


class BacktestCreationContractTests(unittest.TestCase):
    def payload(self):
        return dict(requestId='request_id_12345678', symbol='BTCUSD', balance=1000,
                    startTime='2026-10-01T00:00:00Z', endTime='2026-10-02T00:00:00Z')

    def create(self, uid='alice', **changes):
        return backtest_creation(uid, {**self.payload(), **changes}, allowed_symbols={'BTCUSD'},
                                 now=datetime(2026, 10, 3, tzinfo=timezone.utc))

    def test_subject_binds_session_and_private_simulation_has_no_broker_claim(self):
        first, data = self.create()
        self.assertEqual(first, self.create()[0])
        self.assertNotEqual(first, self.create(uid='bob')[0])
        self.assertEqual(data['userId'], 'alice')
        self.assertEqual(data['source'], 'server_enforced')
        self.assertTrue(same_backtest_creation({**data, 'currentBalance': 900}, data))
        self.assertFalse(same_backtest_creation({**data, 'initialBalance': 999}, data))

    def test_invalid_input_cannot_reach_quota(self):
        for change in ({'balance': True}, {'balance': float('nan')}, {'balance': 0},
                       {'symbol': 'UNKNOWN'}, {'requestId': '../bad'},
                       {'startTime': '2026-10-01'}, {'endTime': '2027-01-01T00:00:00Z'},
                       {'startTime': '2026-10-02T00:00:00Z'}):
            with self.assertRaises(ValueError):
                self.create(**change)


class BacktestApiBoundaryTests(unittest.IsolatedAsyncioTestCase):
    class HttpError(Exception):
        def __init__(self, status_code, detail):
            self.status_code, self.detail = status_code, detail

    def handler(self, verified):
        tree = ast.parse((Path(__file__).resolve().parents[2] / 'server.py').read_text())
        node = next(node for node in tree.body if isinstance(node, ast.AsyncFunctionDef)
                    and node.name == 'create_backtest_session')
        node.decorator_list = []
        ns = dict(BacktestCreateRequest=SimpleNamespace, Header=lambda **kwargs: None,
                  verified_user_id=verified, asyncio=asyncio, HTTPException=self.HttpError,
                  backtest_creation=backtest_creation, same_backtest_creation=same_backtest_creation,
                  datetime=datetime, timezone=timezone, TV_SYMBOL_MAP={'BTCUSD'},
                  Capability=SimpleNamespace(BACKTEST='backtest'))
        exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
                     'server.py', 'exec'), ns)
        return ns['create_backtest_session']

    async def test_invalid_request_stops_before_database_or_quota(self):
        async def allow(*args):
            return 'alice'
        handler = self.handler(allow)
        request = SimpleNamespace(userId='alice', model_dump=lambda: {'requestId': 'bad'})
        with self.assertRaises(self.HttpError) as error:
            await handler(request, 'Bearer alice')
        self.assertEqual(error.exception.status_code, 422)

    async def test_quota_exhaustion_stops_creation_and_existing_retry_skips_charge(self):
        async def allow(*args):
            return 'alice'
        handler = self.handler(allow)
        payload = dict(requestId='request_1234567890', symbol='BTCUSD', balance=1000,
                       startTime='2026-10-01T00:00:00Z', endTime='2026-10-02T00:00:00Z')
        request = SimpleNamespace(userId='alice', requestId=payload['requestId'], model_dump=lambda: payload)
        exists = False
        _, saved = backtest_creation('alice', payload, allowed_symbols={'BTCUSD'},
                                     now=datetime.now(timezone.utc))
        reference = SimpleNamespace(get=lambda: SimpleNamespace(exists=exists, to_dict=lambda: saved))
        handler.__globals__['db'] = SimpleNamespace(collection=lambda name: SimpleNamespace(document=lambda id: reference))
        calls = []
        async def deny(*args, **kwargs):
            calls.append(args)
            raise self.HttpError(429, 'quota_exhausted')
        handler.__globals__['consume_operation_quota'] = deny
        with self.assertRaises(self.HttpError) as error:
            await handler(request, 'Bearer alice')
        self.assertEqual(error.exception.status_code, 429)
        self.assertEqual(len(calls), 1)
        exists = True
        result = await handler(request, 'Bearer alice')
        self.assertEqual(result['status'], 'success')
        self.assertEqual(len(calls), 1, 'Existing session creation retry cannot spend quota')

    async def test_identity_check_precedes_quota_and_database_access(self):
        class Denied(Exception):
            pass
        async def deny(header, claimed):
            self.assertEqual((header, claimed), ('Bearer wrong', 'alice'))
            raise Denied()
        with self.assertRaises(Denied):
            await self.handler(deny)(SimpleNamespace(userId='alice'), 'Bearer wrong')
