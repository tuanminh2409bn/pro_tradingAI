"""Validate private practice-session creation; scores remain client simulations."""
import hashlib
import math
import re
from datetime import datetime, timezone


def backtest_creation(uid: str, request: dict, *, allowed_symbols, now: datetime) -> tuple[str, dict]:
    if not isinstance(request, dict) or not isinstance(uid, str) or not uid:
        raise ValueError('Invalid backtest request')
    operation = request.get('requestId')
    symbol = request.get('symbol')
    balance = request.get('balance')
    if (not isinstance(operation, str) or re.fullmatch(r'[A-Za-z0-9_-]{16,80}', operation) is None
            or not isinstance(symbol, str) or symbol not in allowed_symbols
            or type(balance) not in (int, float) or not math.isfinite(balance)
            or not 0 < balance <= 1_000_000_000):
        raise ValueError('Invalid backtest request')
    times = []
    for key in ('startTime', 'endTime'):
        raw = request.get(key)
        if not isinstance(raw, str) or len(raw) > 40:
            raise ValueError('Invalid backtest dates')
        parsed = datetime.fromisoformat(raw.replace('Z', '+00:00'))
        if parsed.tzinfo is None or parsed.utcoffset() is None:
            raise ValueError('Backtest dates require timezone')
        times.append(parsed.astimezone(timezone.utc))
    start, end = times
    if not start < end <= now or (end - start).days > 730:
        raise ValueError('Invalid backtest history range')
    session_id = hashlib.sha256((uid + ':' + operation).encode()).hexdigest()
    return session_id, {
        'userId': uid, 'symbol': symbol, 'startTime': start.isoformat(), 'endTime': end.isoformat(),
        'initialBalance': float(balance), 'currentBalance': float(balance), 'equity': float(balance),
        'openPL': 0.0, 'speed': 1, 'isPlaying': False, 'status': 'CREATED',
        'createdAt': now, 'source': 'server_enforced',
    }


def same_backtest_creation(saved: dict, expected: dict) -> bool:
    return isinstance(saved, dict) and all(saved.get(key) == expected.get(key) for key in
        ('userId', 'symbol', 'startTime', 'endTime', 'initialBalance', 'source'))
