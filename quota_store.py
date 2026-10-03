"""Authoritative Firestore counters under the existing server-only meta path."""

import hashlib
import threading

# Bounded memory: queue the same subject's local writers before Firestore.
# Firestore transactions still enforce the limit across backend processes.
_SUBJECT_LOCKS = tuple(threading.Lock() for _ in range(256))


def commit_quota(transaction, counter_ref, marker_ref, summary_ref, *, counter_key, window_start, reset_at, limit):
    counter = counter_ref.get(transaction=transaction)
    marker = marker_ref.get(transaction=transaction)
    if marker.exists:
        value = marker.to_dict() or {}
        if value.get('counter_key') != counter_key or value.get('window_start') != window_start:
            raise ValueError('Quota operation identity reused for another counter')
        return value.get('used')
    value = counter.to_dict() or {}
    used = value.get('used', 0) if value.get('window_start') == window_start else 0
    if not isinstance(used, int) or isinstance(used, bool) or used < 0:
        raise ValueError('Invalid authoritative quota counter')
    result = used + 1 if used < limit else None
    if result is not None:
        transaction.set(counter_ref, {'counter_key': counter_key, 'window_start': window_start,
                                     'reset_at': reset_at, 'limit': limit, 'used': result})
        transaction.set(summary_ref, {'apiUsed': result, 'apiLimit': limit,
                                     'resetAt': reset_at, 'source': 'server_enforced'}, merge=True)
    transaction.set(marker_ref, {'counter_key': counter_key, 'window_start': window_start, 'used': result})
    return result


class FirestoreQuotaStore:
    def __init__(self, db, *, operation_id, transactional=None):
        self.db = db
        self.operation_id = operation_id
        self.transactional = transactional

    def consume_if_below(self, *, subject_id, counter_key, window_start, reset_at, limit):
        if not subject_id or not self.operation_id:
            raise ValueError('Quota identity required')
        meta = self.db.collection('users').document(subject_id).collection('meta')
        digest = hashlib.sha256(counter_key.encode()).hexdigest()[:24]
        counter = meta.document('quota-' + digest)
        marker = meta.document('quota-request-' + hashlib.sha256(self.operation_id.encode()).hexdigest())
        transactional = self.transactional
        if transactional is None:
            from google.cloud import firestore
            transactional = firestore.transactional
        subject_lock = _SUBJECT_LOCKS[int(hashlib.sha256(subject_id.encode()).hexdigest()[:2], 16)]
        with subject_lock:
            return transactional(commit_quota)(self.db.transaction(max_attempts=20), counter, marker, meta.document('quota'),
                counter_key=counter_key, window_start=window_start, reset_at=reset_at, limit=limit)
