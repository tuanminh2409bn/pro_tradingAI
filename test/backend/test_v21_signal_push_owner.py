"""Ensure a private signal cannot be broadcast to another user's FCM token."""

from __future__ import annotations

import ast
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
    def __init__(self, name, users):
        self.name = name
        self.users = users

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
        return SimpleNamespace(get=lambda: Snapshot(self.users.get(uid)))


def load_sender(users, sent):
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
        send_each_for_multicast=lambda message: sent.append(message) or SimpleNamespace(
            success_count=1, failure_count=0, responses=[]
        ),
    )
    namespace = {
        'db': SimpleNamespace(collection=lambda name: FakeCollection(name, users)),
        'messaging': messaging,
        'push_recipient_opted_in': push_recipient_opted_in,
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
        send('alice', 'XAUUSD', 'BUY', 2500, 2490, [2520], 80)
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0].tokens, ['alice-token'])

    def test_owner_opt_out_prevents_delivery(self):
        sent = []
        send = load_sender({'alice': {'pushNotificationsEnabled': False}}, sent)
        send('alice', 'XAUUSD', 'BUY', 2500, 2490, [2520], 80)
        self.assertEqual(sent, [])


if __name__ == '__main__':
    unittest.main()
