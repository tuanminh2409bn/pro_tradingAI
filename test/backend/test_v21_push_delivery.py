import unittest
from dataclasses import fields

from entitlements import AccountRole, VerifiedQuotaIdentity
from push_delivery import (
    DeviceType,
    ManualPushRequest,
    ManualPushService,
    PushDeepLink,
    PushDeliveryDenied,
    PushPolicy,
    PushProviderResult,
    PushRecipient,
    PushSegment,
)


class StubRecipientStore:
    def __init__(self, recipients):
        self.recipients = recipients
        self.list_calls = 0
        self.retired = []

    def list_recipients(self):
        self.list_calls += 1
        return self.recipients

    def retire_token_refs(self, *, token_refs):
        self.retired.append(tuple(token_refs))


class StubProvider:
    def __init__(self, result_factory=None):
        self.calls = []
        self.result_factory = result_factory

    def send(self, *, token_refs, title, body, data):
        self.calls.append((tuple(token_refs), title, body, dict(data)))
        if self.result_factory is not None:
            return self.result_factory(tuple(token_refs))
        return PushProviderResult(
            delivered_token_refs=tuple(token_refs),
            invalid_token_refs=(),
            failed_token_refs=(),
        )


class StubAuditStore:
    def __init__(self):
        self.records = []

    def append(self, *, record):
        self.records.append(record)
        return "audit-1"


class PushDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.admin = VerifiedQuotaIdentity(
            uid="admin-1", role=AccountRole.STANDARD, is_admin=True
        )
        self.policy = PushPolicy(
            max_title_chars=80,
            max_body_chars=500,
            max_recipients=500,
        )
        self.recipients = (
            PushRecipient(
                uid="u1",
                role=AccountRole.PROFESSIONAL,
                country="VN",
                device=DeviceType.WEB,
                opted_in=True,
                token_ref="token-ref-1",
            ),
            PushRecipient(
                uid="u2",
                role=AccountRole.PROFESSIONAL,
                country="US",
                device=DeviceType.IOS,
                opted_in=True,
                token_ref="token-ref-2",
            ),
            PushRecipient(
                uid="u3",
                role=AccountRole.ENTERPRISE,
                country="VN",
                device=DeviceType.WEB,
                opted_in=True,
                token_ref="token-ref-3",
            ),
            PushRecipient(
                uid="u4",
                role=AccountRole.PROFESSIONAL,
                country="VN",
                device=DeviceType.WEB,
                opted_in=False,
                token_ref="token-ref-4",
            ),
        )

    def make_request(self, *, segment=PushSegment()):
        return ManualPushRequest(
            request_id="push-request-1",
            title="Market update",
            body="A traceable Radar confirmation is available.",
            segment=segment,
            deep_link=PushDeepLink(
                tab="trading_room",
                symbol="XAUUSD",
                timeframe="M5",
                closed_at=1_700_006_000,
            ),
        )

    def make_service(self, *, recipients=None, provider=None):
        recipient_store = StubRecipientStore(
            self.recipients if recipients is None else recipients
        )
        provider = provider or StubProvider()
        audit_store = StubAuditStore()
        service = ManualPushService(
            recipient_store=recipient_store,
            provider=provider,
            audit_store=audit_store,
            policy=self.policy,
        )
        return service, recipient_store, provider, audit_store

    def test_segment_selection_is_server_side_and_honors_opt_out(self):
        service, _, provider, audit_store = self.make_service()
        summary = service.send(
            identity=self.admin,
            request=self.make_request(
                segment=PushSegment(
                    roles=frozenset({AccountRole.PROFESSIONAL}),
                    countries=frozenset({"VN"}),
                    devices=frozenset({DeviceType.WEB}),
                )
            ),
        )

        self.assertEqual(provider.calls[0][0], ("token-ref-1",))
        self.assertEqual(provider.calls[0][3]["symbol"], "XAUUSD")
        self.assertEqual(provider.calls[0][3]["timeframe"], "M5")
        self.assertEqual(summary.targeted_count, 1)
        self.assertEqual(audit_store.records[0].targeted_count, 1)

    def test_non_admin_and_invalid_payload_fail_before_recipient_query(self):
        service, recipient_store, _, _ = self.make_service()
        non_admin = VerifiedQuotaIdentity(
            uid="u1", role=AccountRole.ENTERPRISE
        )
        with self.assertRaises(PushDeliveryDenied):
            service.send(identity=non_admin, request=self.make_request())
        self.assertEqual(recipient_store.list_calls, 0)

        oversized = ManualPushRequest(
            request_id="push-request-2",
            title="x" * 81,
            body="body",
            segment=PushSegment(),
            deep_link=None,
        )
        with self.assertRaises(PushDeliveryDenied):
            service.send(identity=self.admin, request=oversized)
        self.assertEqual(recipient_store.list_calls, 0)

    def test_empty_recipient_selection_is_rejected_without_provider_call(self):
        service, _, provider, audit_store = self.make_service(recipients=())
        with self.assertRaises(PushDeliveryDenied):
            service.send(identity=self.admin, request=self.make_request())
        self.assertEqual(provider.calls, [])
        self.assertEqual(audit_store.records, [])

    def test_invalid_tokens_are_retired_and_never_exposed_by_summary_or_audit(self):
        provider = StubProvider(
            result_factory=lambda refs: PushProviderResult(
                delivered_token_refs=refs[:1],
                invalid_token_refs=refs[1:2],
                failed_token_refs=refs[2:],
            )
        )
        service, recipient_store, _, audit_store = self.make_service(
            provider=provider
        )
        summary = service.send(identity=self.admin, request=self.make_request())

        self.assertEqual(recipient_store.retired, [("token-ref-2",)])
        self.assertEqual(summary.delivered_count, 1)
        self.assertEqual(summary.invalid_count, 1)
        self.assertEqual(summary.failed_count, 1)
        for model in (summary, audit_store.records[0]):
            model_fields = {field.name for field in fields(model)}
            self.assertFalse(any("token" in name for name in model_fields))
            self.assertNotIn("token-ref", repr(model))

    def test_provider_result_must_partition_exact_target_set(self):
        provider = StubProvider(
            result_factory=lambda refs: PushProviderResult(
                delivered_token_refs=("not-a-target",),
                invalid_token_refs=(),
                failed_token_refs=(),
            )
        )
        service, _, _, audit_store = self.make_service(provider=provider)
        with self.assertRaises(PushDeliveryDenied):
            service.send(identity=self.admin, request=self.make_request())
        self.assertEqual(audit_store.records, [])


if __name__ == "__main__":
    unittest.main()
