import unittest
from datetime import datetime, timedelta, timezone

from entitlements import (
    AccountRole,
    PurchaseDenied,
    PurchaseEntitlementService,
    PurchaseState,
    VerifiedPurchaseReceipt,
    VerifiedQuotaIdentity,
    should_show_standard_ad,
)


class StubReceiptVerifier:
    def __init__(self, result):
        self.result = result
        self.calls = []

    def verify(self, *, receipt, product_id, platform):
        self.calls.append((receipt, product_id, platform))
        return self.result


class PurchaseEntitlementTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 9, 12, 10, tzinfo=timezone.utc)
        self.standard = VerifiedQuotaIdentity(
            uid="user-1", role=AccountRole.STANDARD
        )

    def test_only_consented_standard_user_sees_approved_placement(self):
        approved = {"trading_room_footer", "news_feed_inline"}
        self.assertTrue(
            should_show_standard_ad(
                identity=self.standard,
                placement_id="trading_room_footer",
                approved_placements=approved,
                ads_consent=True,
            )
        )
        self.assertFalse(
            should_show_standard_ad(
                identity=self.standard,
                placement_id="unknown",
                approved_placements=approved,
                ads_consent=True,
            )
        )
        self.assertFalse(
            should_show_standard_ad(
                identity=self.standard,
                placement_id="trading_room_footer",
                approved_placements=approved,
                ads_consent=False,
            )
        )

        for identity in (
            VerifiedQuotaIdentity(
                uid="partner", role=AccountRole.VERIFIED_PARTNER
            ),
            VerifiedQuotaIdentity(
                uid="professional", role=AccountRole.PROFESSIONAL
            ),
            VerifiedQuotaIdentity(
                uid="enterprise", role=AccountRole.ENTERPRISE
            ),
            VerifiedQuotaIdentity(
                uid="admin", role=AccountRole.STANDARD, is_admin=True
            ),
        ):
            self.assertFalse(
                should_show_standard_ad(
                    identity=identity,
                    placement_id="trading_room_footer",
                    approved_placements=approved,
                    ads_consent=True,
                )
            )

    def test_valid_server_receipt_grants_only_professional_entitlement(self):
        verified = VerifiedPurchaseReceipt(
            subject_uid="user-1",
            product_id="protrading_professional_monthly",
            transaction_id="transaction-1",
            state=PurchaseState.ACTIVE,
            expires_at=self.now + timedelta(days=30),
        )
        verifier = StubReceiptVerifier(verified)
        service = PurchaseEntitlementService(
            verifier=verifier,
            professional_product_ids={"protrading_professional_monthly"},
        )

        grant = service.validate_professional_purchase(
            identity=self.standard,
            receipt="opaque-store-receipt",
            product_id="protrading_professional_monthly",
            platform="apple",
            now=self.now,
        )

        self.assertEqual(grant.role, AccountRole.PROFESSIONAL)
        self.assertEqual(grant.subject_uid, "user-1")
        self.assertEqual(grant.source, "verified_iap")
        self.assertEqual(len(verifier.calls), 1)

    def test_mismatch_refund_revocation_and_expiry_fail_closed(self):
        invalid_receipts = (
            VerifiedPurchaseReceipt(
                subject_uid="another-user",
                product_id="protrading_professional_monthly",
                transaction_id="transaction-1",
                state=PurchaseState.ACTIVE,
                expires_at=self.now + timedelta(days=30),
            ),
            VerifiedPurchaseReceipt(
                subject_uid="user-1",
                product_id="protrading_professional_monthly",
                transaction_id="transaction-2",
                state=PurchaseState.REFUNDED,
                expires_at=self.now + timedelta(days=30),
            ),
            VerifiedPurchaseReceipt(
                subject_uid="user-1",
                product_id="protrading_professional_monthly",
                transaction_id="transaction-3",
                state=PurchaseState.REVOKED,
                expires_at=self.now + timedelta(days=30),
            ),
            VerifiedPurchaseReceipt(
                subject_uid="user-1",
                product_id="protrading_professional_monthly",
                transaction_id="transaction-4",
                state=PurchaseState.ACTIVE,
                expires_at=self.now,
            ),
        )
        for receipt in invalid_receipts:
            service = PurchaseEntitlementService(
                verifier=StubReceiptVerifier(receipt),
                professional_product_ids={
                    "protrading_professional_monthly"
                },
            )
            with self.assertRaises(PurchaseDenied):
                service.validate_professional_purchase(
                    identity=self.standard,
                    receipt="opaque-store-receipt",
                    product_id="protrading_professional_monthly",
                    platform="google",
                    now=self.now,
                )

    def test_unapproved_product_or_malformed_receipt_never_reaches_verifier(self):
        verifier = StubReceiptVerifier(
            VerifiedPurchaseReceipt(
                subject_uid="user-1",
                product_id="protrading_professional_monthly",
                transaction_id="transaction-1",
                state=PurchaseState.ACTIVE,
                expires_at=self.now + timedelta(days=30),
            )
        )
        service = PurchaseEntitlementService(
            verifier=verifier,
            professional_product_ids={"protrading_professional_monthly"},
        )
        for receipt, product, platform in (
            ("", "protrading_professional_monthly", "apple"),
            ("receipt", "client_selected_enterprise", "apple"),
            ("receipt", "protrading_professional_monthly", "web"),
        ):
            with self.assertRaises((ValueError, PurchaseDenied)):
                service.validate_professional_purchase(
                    identity=self.standard,
                    receipt=receipt,
                    product_id=product,
                    platform=platform,
                    now=self.now,
                )
        self.assertEqual(verifier.calls, [])


if __name__ == "__main__":
    unittest.main()
