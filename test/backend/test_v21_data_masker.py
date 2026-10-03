import unittest
from dataclasses import fields
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from data_masker import (
    DataLakeDeletionService,
    DataLakeExportDenied,
    DataLakeMasker,
    DataLakePolicy,
    DataLakeSubject,
)


class StubDeletionStore:
    def __init__(self, deleted_count=3):
        self.deleted_count = deleted_count
        self.calls = []

    def delete_subject(self, *, subject_ref):
        self.calls.append(subject_ref)
        return self.deleted_count


class DataMaskerTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 9, 12, 12, tzinfo=timezone.utc)
        self.policy = DataLakePolicy(
            pseudonym_key=b"k" * 32,
            pseudonym_key_id="key-2026-09",
            consent_version="privacy-v2.1",
            retention_days=30,
            allowed_event_types=frozenset({"analysis_completed"}),
        )
        self.subject = DataLakeSubject(
            uid="private-user-123",
            consent_granted=True,
            consent_version="privacy-v2.1",
            deletion_requested_at=None,
        )
        self.event = {
            "event_type": "analysis_completed",
            "occurred_at": self.now - timedelta(days=1),
            "symbol": "XAUUSD",
            "timeframe": "M5",
            "percentage_growth": Decimal("1.25"),
            "unit_volume": Decimal("3"),
            "country": "VN",
            "device_type": "web",
            "outcome": "success",
        }

    def test_masked_record_contains_stable_pseudonym_and_no_raw_identity(self):
        first = DataLakeMasker(policy=self.policy).mask(
            subject=self.subject, event=self.event, now=self.now
        )
        second = DataLakeMasker(policy=self.policy).mask(
            subject=self.subject, event=dict(self.event), now=self.now
        )

        self.assertEqual(first.subject_ref, second.subject_ref)
        self.assertNotIn(self.subject.uid, repr(first))
        self.assertEqual(first.pseudonym_key_id, "key-2026-09")
        self.assertEqual(
            first.expires_at,
            self.event["occurred_at"] + timedelta(days=30),
        )
        self.assertEqual(
            {field.name for field in fields(first)},
            {
                "subject_ref",
                "pseudonym_key_id",
                "event_type",
                "occurred_at",
                "expires_at",
                "symbol",
                "timeframe",
                "percentage_growth",
                "unit_volume",
                "country",
                "device_type",
                "outcome",
            },
        )

    def test_sensitive_and_unknown_fields_fail_closed_instead_of_redacting_guesswork(self):
        sensitive_keys = (
            "email",
            "ip",
            "account_id",
            "auth_token",
            "password",
            "credential",
            "fcm_token",
        )
        masker = DataLakeMasker(policy=self.policy)
        for key in sensitive_keys:
            event = dict(self.event)
            event[key] = "must-never-export"
            with self.assertRaises(DataLakeExportDenied):
                masker.mask(subject=self.subject, event=event, now=self.now)
        event = dict(self.event)
        event["metadata"] = {"email": "nested@example.com"}
        with self.assertRaises(DataLakeExportDenied):
            masker.mask(subject=self.subject, event=event, now=self.now)

    def test_consent_version_deletion_and_retention_are_enforced(self):
        subjects = (
            DataLakeSubject("u1", False, "privacy-v2.1", None),
            DataLakeSubject("u1", True, "old-policy", None),
            DataLakeSubject("u1", True, "privacy-v2.1", self.now),
        )
        masker = DataLakeMasker(policy=self.policy)
        for subject in subjects:
            with self.assertRaises(DataLakeExportDenied):
                masker.mask(subject=subject, event=self.event, now=self.now)

        expired = dict(self.event)
        expired["occurred_at"] = self.now - timedelta(days=30)
        with self.assertRaises(DataLakeExportDenied):
            masker.mask(subject=self.subject, event=expired, now=self.now)

    def test_key_rotation_changes_pseudonym_without_exposing_uid(self):
        first = DataLakeMasker(policy=self.policy).mask(
            subject=self.subject, event=self.event, now=self.now
        )
        rotated = DataLakePolicy(
            pseudonym_key=b"z" * 32,
            pseudonym_key_id="key-2026-10",
            consent_version="privacy-v2.1",
            retention_days=30,
            allowed_event_types=frozenset({"analysis_completed"}),
        )
        second = DataLakeMasker(policy=rotated).mask(
            subject=self.subject, event=self.event, now=self.now
        )
        self.assertNotEqual(first.subject_ref, second.subject_ref)
        self.assertNotIn(self.subject.uid, repr(second))

    def test_deletion_store_receives_only_pseudonymous_subject_reference(self):
        store = StubDeletionStore()
        result = DataLakeDeletionService(
            policy=self.policy, store=store
        ).delete(subject=self.subject)

        self.assertEqual(result.deleted_count, 3)
        self.assertEqual(store.calls, [result.subject_ref])
        self.assertNotIn(self.subject.uid, repr(result))
        self.assertNotIn("uid", {field.name for field in fields(result)})


if __name__ == "__main__":
    unittest.main()
