"""Authoritative Firestore counters under the existing server-only meta path."""

import hashlib
import threading

# Bounded memory: queue the same subject's local writers before Firestore.
# Firestore transactions still enforce the limit across backend processes.
_SUBJECT_LOCKS = tuple(threading.Lock() for _ in range(256))


def commit_quota(transaction, counter_ref, marker_ref, summary_ref, *, counter_key, window_start, reset_at, limit,
                 session_ref=None, session_data=None):
    counter = counter_ref.get(transaction=transaction)
    marker = marker_ref.get(transaction=transaction)
    session = session_ref.get(transaction=transaction) if session_ref is not None else None
    if session is not None and session.exists:
        saved = session.to_dict() or {}
        if any(saved.get(key) != session_data.get(key) for key in
               ('userId', 'symbol', 'startTime', 'endTime', 'initialBalance', 'source')):
            raise ValueError('Backtest operation identity reused for another session')
        if not marker.exists:
            raise ValueError('Backtest allocation lacks authoritative quota')
    if marker.exists:
        value = marker.to_dict() or {}
        if value.get('counter_key') != counter_key or value.get('window_start') != window_start:
            raise ValueError('Quota operation identity reused for another counter')
        if session is not None and value.get('used') is not None and not session.exists:
            raise ValueError('Backtest allocation is unavailable')
        return value.get('used')
    value = counter.to_dict() or {}
    used = value.get('used', 0) if value.get('window_start') == window_start else 0
    if not isinstance(used, int) or isinstance(used, bool) or used < 0:
        raise ValueError('Invalid authoritative quota counter')
    result = used + 1 if used < limit else None
    if result is not None:
        transaction.set(counter_ref, {'counter_key': counter_key, 'window_start': window_start,
                                     'reset_at': reset_at, 'limit': limit, 'used': result})
        backtest = ':backtest:' in counter_key
        transaction.set(summary_ref, {
            'backtestUsed' if backtest else 'apiUsed': result,
            'backtestLimit' if backtest else 'apiLimit': limit,
            'backtestResetAt' if backtest else 'resetAt': reset_at,
            'source': 'server_enforced'}, merge=True)
        if session_ref is not None:
            transaction.set(session_ref, session_data)
    transaction.set(marker_ref, {'counter_key': counter_key, 'window_start': window_start, 'used': result})
    return result


class FirestoreQuotaStore:
    def __init__(self, db, *, operation_id, transactional=None, session_ref=None, session_data=None):
        self.db = db
        self.operation_id = operation_id
        self.transactional = transactional
        if (session_ref is None) != (session_data is None):
            raise ValueError('Backtest allocation requires reference and data')
        self.session_ref, self.session_data = session_ref, session_data

    def consume_if_below(self, *, subject_id, counter_key, window_start, reset_at, limit):
        if not subject_id or not self.operation_id:
            raise ValueError('Quota identity required')
        if self.session_data is not None and (
            self.session_data.get('userId') != subject_id or ':backtest:' not in counter_key
        ):
            raise ValueError('Backtest allocation identity mismatch')
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
                counter_key=counter_key, window_start=window_start, reset_at=reset_at, limit=limit,
                session_ref=self.session_ref, session_data=self.session_data)
