"""Ensure a private signal cannot be broadcast to another user's FCM token."""

from __future__ import annotations

import ast
import re
from urllib.parse import urlencode
import unittest
from pathlib import Path
from types import SimpleNamespace

from push_preferences import push_recipient_opted_in


class Snapshot:
    def __init__(self, data):
        self.exists = data is not None
        self.data = data

    def to_dict(self):
        return self.data


class FakeCollection:
    def __init__(self, name, users, retired):
        self.name = name
        self.users = users
        self.retired = retired

    def where(self, field, operator, value):
        assert (field, operator, value) == ('userId', '==', 'alice')
        return self

    def get(self):
        # Include a foreign token even if the query layer misbehaves.
        return [
            Snapshot({'userId': 'alice', 'token': 'alice-token'}),
            Snapshot({'userId': 'bob', 'token': 'bob-token'}),
        ]

    def document(self, uid):
        return SimpleNamespace(get=lambda: Snapshot(self.users.get(uid)), delete=lambda: self.retired.append(uid))


def load_sender(users, sent, *, failure=None, retired=None, error_message='provider-unavailable'):
    source = (Path(__file__).resolve().parents[2] / 'server.py').read_text(encoding='utf-8')
    node = next(
        node for node in ast.parse(source).body
        if isinstance(node, ast.FunctionDef) and node.name == 'send_signal_push_to_owner'
    )
    messaging = SimpleNamespace(
        MulticastMessage=lambda **kwargs: SimpleNamespace(**kwargs),
        Notification=lambda **kwargs: kwargs,
        WebpushConfig=lambda **kwargs: kwargs,
        WebpushNotification=lambda **kwargs: kwargs,
        WebpushFCMOptions=lambda **kwargs: kwargs,
        UnregisteredError=type('UnregisteredError', (Exception,), {}),
        send_each_for_multicast=lambda message: sent.append(message) or SimpleNamespace(
            success_count=1, failure_count=0, responses=[]
        ),
    )
    if failure:
        error = messaging.UnregisteredError(error_message) if failure == 'invalid' else RuntimeError(error_message)
        messaging.send_each_for_multicast = lambda message: sent.append(message) or SimpleNamespace(
            success_count=0, failure_count=1, responses=[SimpleNamespace(success=False, exception=error)])
    namespace = {
        'db': SimpleNamespace(collection=lambda name: FakeCollection(name, users, retired if retired is not None else [])),
        'messaging': messaging,
        'push_recipient_opted_in': push_recipient_opted_in,
        're': re, 'urlencode': urlencode,
    }
    exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])), 'server.py', 'exec'), namespace)
    return namespace['send_signal_push_to_owner']


class SignalPushOwnerTests(unittest.TestCase):
    def test_only_opted_in_owner_receives_private_signal(self):
        sent = []
        send = load_sender({
            'alice': {'pushNotificationsEnabled': True},
            'bob': {'pushNotificationsEnabled': True},
        }, sent)
        send('alice', 'XAUUSD', 'BUY', 2500, 2490, [2520], 80, timeframe='240', closed_at=1791158400)
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0].tokens, ['alice-token'])
        self.assertEqual(sent[0].data['timeframe'], 'H4')
        self.assertIn('symbol=XAUUSD', sent[0].webpush['fcm_options']['link'])

    def test_owner_opt_out_prevents_delivery(self):
        sent = []
        send = load_sender({'alice': {'pushNotificationsEnabled': False}}, sent)
        send('alice', 'XAUUSD', 'BUY', 2500, 2490, [2520], 80)
        self.assertEqual(sent, [])

    def test_transient_failure_preserves_token_but_provider_confirmed_invalid_is_retired(self):
        for failure, expected in (('transient', []), ('invalid', ['alice-token'])):
            retired = []
            send = load_sender({'alice': {'pushNotificationsEnabled': True}}, [], failure=failure, retired=retired)
            send('alice', 'XAUUSD', 'BUY', 2500, 2490, [2520], 80)
            self.assertEqual(retired, expected)


if __name__ == '__main__':
    unittest.main()
