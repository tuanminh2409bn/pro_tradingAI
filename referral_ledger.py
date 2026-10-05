"""Integer-only referral accounting. All mutations run in a Firestore transaction."""
from datetime import datetime, timedelta, timezone
import hashlib
import re


class LedgerDenied(ValueError):
    pass


POLICY_VERSION = 'manual-subscription-v1'
MIN_WITHDRAWAL = 2000  # USD cents; manual Admin review does not transfer money.
RATES_BPS = (2000, 500)


def opaque_id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]{16,96}', value):
        raise LedgerDenied('Invalid reference')
    return value


def minor_units(value, *, positive=False):
    if type(value) is not int or abs(value) > 10**12 or (positive and value <= 0):
        raise LedgerDenied('Invalid amount')
    return value


def wallet_state(data):
    if not isinstance(data, dict) or data.get('currency') != 'USD' or data.get('source') != 'admin_verified_receipts' or data.get('policyVersion') != POLICY_VERSION:
        raise LedgerDenied('Verified ledger unavailable')
    result = {k: minor_units(data.get(k)) for k in ('creditsMinor', 'reversedMinor', 'heldMinor', 'paidMinor')}
    if any(v < 0 for v in result.values()) or result['reversedMinor'] > result['creditsMinor'] or result['heldMinor'] + result['paidMinor'] > result['creditsMinor']:
        raise LedgerDenied('Invalid wallet')
    pending = data.get('pendingRequestId')
    if pending is not None and (not isinstance(pending, str) or not re.fullmatch(r'[a-f0-9]{64}', pending)):
        raise LedgerDenied('Invalid reservation')
    return {**result, 'currency': 'USD', 'source': 'admin_verified_receipts', 'policyVersion': POLICY_VERSION, 'pendingRequestId': pending}


def available(wallet):
    return wallet['creditsMinor'] - wallet['reversedMinor'] - wallet['heldMinor'] - wallet['paidMinor']


def private_ref(client, uid, collection, ident):
    if not isinstance(uid, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', uid):
        raise LedgerDenied('Invalid account')
    return client.collection('users').document(uid).collection(collection).document(ident)


def _snapshot(ref, transaction):
    snapshot = ref.get(transaction=transaction)
    return snapshot.to_dict() if snapshot.exists else None


def _wallet_ref(client, uid):
    return private_ref(client, uid, 'meta', 'referral_wallet')


def commit_receipt(transaction, client, receipt, actor_uid, now):
    """Import an Admin-reviewed settled subscription receipt, never trading P&L."""
    reference = opaque_id(receipt['receiptId'])
    payer = receipt['payerUid']
    amount = minor_units(receipt['netMinor'], positive=True)
    if not isinstance(receipt.get('settledAt'), str) or len(receipt['settledAt']) > 40:
        raise LedgerDenied('Invalid settlement time')
    try:
        settled = datetime.fromisoformat(receipt['settledAt'].replace('Z', '+00:00'))
    except (ValueError, TypeError, AttributeError):
        raise LedgerDenied('Invalid settlement time') from None
    if settled.tzinfo is None or settled.utcoffset() != timedelta(0) or now - settled < timedelta(days=14):
        raise LedgerDenied('Receipt has not completed the settlement hold')
    private_ref(client, payer, 'meta', 'referral_wallet')  # validate UID
    receipt_key = hashlib.sha256(('manual-subscription:' + reference).encode()).hexdigest()
    receipt_ref = client.collection('referral_receipts').document(receipt_key)
    previous = _snapshot(receipt_ref, transaction)
    intent = dict(payerUid=payer, netMinor=amount, settledAt=settled, policyVersion=POLICY_VERSION)
    if previous:
        if any(previous.get(k) != v for k, v in intent.items()):
            raise LedgerDenied('Receipt reference conflict')
        return {'status': 'restored', 'receiptId': receipt_key}
    recipients, current = [], payer
    seen = {payer}
    for rate in RATES_BPS:
        attribution = _snapshot(private_ref(client, current, 'meta', 'referral_attribution'), transaction)
        if not attribution:
            break
        attributed_at = attribution.get('createdAt')
        if not isinstance(attributed_at, datetime) or attributed_at.tzinfo is None or attributed_at > settled:
            raise LedgerDenied('Attribution must precede the receipt')
        code = attribution.get('code')
        if not isinstance(code, str) or not re.fullmatch(r'[A-Za-z0-9_-]{24}', code):
            raise LedgerDenied('Invalid attribution')
        registry = _snapshot(client.collection('referral_codes').document(code), transaction)
        recipient = (registry or {}).get('userId')
        if recipient in seen:
            raise LedgerDenied('Referral cycle')
        wallet_ref = _wallet_ref(client, recipient)
        wallet_data = _snapshot(wallet_ref, transaction)
        wallet = wallet_state(wallet_data) if wallet_data else dict(creditsMinor=0, reversedMinor=0, heldMinor=0, paidMinor=0, currency='USD', source='admin_verified_receipts', policyVersion=POLICY_VERSION)
        recipients.append((recipient, amount * rate // 10000, wallet_ref, wallet))
        seen.add(recipient)
        current = recipient
    if not recipients:
        raise LedgerDenied('Receipt has no eligible referral attribution')
    for level, (uid, credit, wallet_ref, wallet) in enumerate(recipients, 1):
        if credit == 0:
            continue
        wallet['creditsMinor'] += credit
        transaction.set(wallet_ref, wallet_state(wallet))
        transaction.create(private_ref(client, uid, 'referral_ledger', receipt_key), {
            'kind': 'CREDIT', 'amountMinor': credit, 'currency': 'USD', 'level': level,
            'receiptId': receipt_key, 'createdAt': now, 'actorUid': actor_uid, 'policyVersion': POLICY_VERSION,
        })
    transaction.create(receipt_ref, {**intent, 'createdAt': now, 'actorUid': actor_uid,
        'source': 'admin_verified_subscription', 'recipients': [{'uid': uid, 'amountMinor': credit} for uid, credit, _, _ in recipients], 'reversed': False})
    return {'status': 'recorded', 'receiptId': receipt_key}


def commit_withdrawal(transaction, client, uid, request_id, amount, now):
    opaque_id(request_id)
    minor_units(amount, positive=True)
    if amount < MIN_WITHDRAWAL:
        raise LedgerDenied('Withdrawal minimum is USD 20')
    key = hashlib.sha256((uid + ':' + request_id).encode()).hexdigest()
    request_ref = private_ref(client, uid, 'referral_withdrawals', key)
    previous = _snapshot(request_ref, transaction)
    if previous:
        if previous.get('amountMinor') != amount:
            raise LedgerDenied('Withdrawal reference conflict')
        return {'requestId': key, 'status': previous['status']}
    wallet_ref = _wallet_ref(client, uid)
    wallet = wallet_state(_snapshot(wallet_ref, transaction))
    if wallet['pendingRequestId'] is not None:
        raise LedgerDenied('An existing withdrawal requires review')
    if amount > available(wallet):
        raise LedgerDenied('Insufficient available balance')
    wallet['heldMinor'] += amount
    wallet['pendingRequestId'] = key
    record = dict(amountMinor=amount, currency='USD', status='PENDING', createdAt=now, policyVersion=POLICY_VERSION)
    transaction.set(wallet_ref, wallet)
    transaction.create(request_ref, record)
    transaction.create(private_ref(client, uid, 'referral_ledger', key + '_hold'), dict(kind='HOLD', amountMinor=amount, currency='USD', requestId=key, createdAt=now))
    transaction.create(client.collection('admin').document('requests').collection('pending').document(key),
        dict(userId=uid, type='REFERRAL_WITHDRAWAL', amount='USD {:.2f}'.format(amount / 100), amountMinor=amount, currency='USD', status='PENDING', date=now))
    return {'requestId': key, 'status': 'PENDING'}


def commit_withdrawal_review(transaction, client, request_id, action, payment_reference, actor_uid, now):
    opaque_id(request_id)
    if action not in ('approve', 'reject', 'paid') or (action != 'paid' and payment_reference is not None):
        raise LedgerDenied('Invalid review action')
    admin_ref = client.collection('admin').document('requests').collection('pending').document(request_id)
    admin = _snapshot(admin_ref, transaction)
    if not admin or admin.get('type') != 'REFERRAL_WITHDRAWAL':
        raise LedgerDenied('Withdrawal unavailable')
    uid = admin['userId']
    request_ref = private_ref(client, uid, 'referral_withdrawals', request_id)
    request = _snapshot(request_ref, transaction)
    if not request or request.get('amountMinor') != admin.get('amountMinor') or request.get('status') != admin.get('status'):
        raise LedgerDenied('Withdrawal state mismatch')
    status = {'approve': 'APPROVED', 'reject': 'REJECTED', 'paid': 'PAID'}[action]
    if request['status'] == status:
        if action == 'paid' and request.get('paymentReference') != payment_reference:
            raise LedgerDenied('Payment reference conflict')
        return {'status': status}
    if request['status'] not in ('PENDING', 'APPROVED') or (action == 'approve' and request['status'] != 'PENDING') or (action == 'paid' and request['status'] != 'APPROVED'):
        raise LedgerDenied('Invalid withdrawal transition')
    wallet_ref = _wallet_ref(client, uid)
    wallet = wallet_state(_snapshot(wallet_ref, transaction))
    amount = minor_units(request['amountMinor'], positive=True)
    if wallet['heldMinor'] < amount or wallet['pendingRequestId'] != request_id:
        raise LedgerDenied('Invalid reservation')
    payout_ref = None
    if action == 'paid':
        opaque_id(payment_reference)
        if available(wallet) < 0:
            raise LedgerDenied('Withdrawal requires financial review')
        payout_ref = client.collection('referral_payout_receipts').document(hashlib.sha256(payment_reference.encode()).hexdigest())
        if _snapshot(payout_ref, transaction):
            raise LedgerDenied('Payment reference already used')
        wallet['heldMinor'] -= amount
        wallet['paidMinor'] += amount
    elif action == 'reject':
        wallet['heldMinor'] -= amount
    if action != 'approve':
        wallet['pendingRequestId'] = None
        transaction.set(wallet_ref, wallet)
        transaction.create(private_ref(client, uid, 'referral_ledger', request_id + '_' + action), dict(kind='PAYOUT' if action == 'paid' else 'RELEASE', amountMinor=amount, currency='USD', requestId=request_id, createdAt=now, actorUid=actor_uid))
    if payout_ref:
        transaction.create(payout_ref, dict(requestId=request_id, userId=uid, amountMinor=amount, currency='USD', createdAt=now, actorUid=actor_uid))
    update = dict(status=status, reviewedAt=now, actorUid=actor_uid)
    if action == 'paid':
        update['paymentReference'] = payment_reference
    transaction.update(request_ref, update)
    transaction.update(admin_ref, update)
    return {'status': status}


def commit_receipt_reversal(transaction, client, receipt_id, actor_uid, now):
    opaque_id(receipt_id)
    receipt_ref = client.collection('referral_receipts').document(receipt_id)
    receipt = _snapshot(receipt_ref, transaction)
    if not receipt:
        raise LedgerDenied('Receipt unavailable')
    if receipt.get('reversed') is True:
        return {'status': 'restored'}
    wallets = []
    for item in receipt['recipients']:
        if item['amountMinor'] == 0:
            continue
        ref = _wallet_ref(client, item['uid'])
        state = wallet_state(_snapshot(ref, transaction))
        state['reversedMinor'] += minor_units(item['amountMinor'], positive=True)
        wallets.append((item, ref, wallet_state(state)))
    for item, ref, wallet in wallets:
        transaction.set(ref, wallet)
        transaction.create(private_ref(client, item['uid'], 'referral_ledger', receipt_id + '_reversal'), dict(kind='REVERSAL', amountMinor=item['amountMinor'], currency='USD', receiptId=receipt_id, createdAt=now, actorUid=actor_uid))
    transaction.update(receipt_ref, dict(reversed=True, reversedAt=now, reversedBy=actor_uid))
    return {'status': 'reversed'}
