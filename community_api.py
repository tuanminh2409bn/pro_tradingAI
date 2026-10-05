"""Pure validation and opaque, owner-bound IDs for Community writes."""

import hashlib
import json
import re
import math
from datetime import datetime, timedelta


def community_write_intent(user_id, request_id, raw_content, post_id=None):
    if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,80}", request_id):
        raise ValueError("Invalid request ID")
    if post_id is not None and (
        not isinstance(post_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", post_id)
    ):
        raise ValueError("Invalid post ID")
    if not isinstance(raw_content, str):
        raise ValueError("Invalid content")
    content = raw_content.strip()
    if not content or len(content) > (1000 if post_id is not None else 2000):
        raise ValueError("Invalid content")
    identity = json.dumps([user_id, post_id, request_id], separators=(",", ":"))
    return hashlib.sha256(identity.encode("utf-8")).hexdigest(), content


def verified_leaderboard_entry(public_id, data, now):
    """Return only a verified public DTO; reject legacy/private-field documents."""
    fields = {'schemaVersion', 'source', 'isServerVerified', 'displayName', 'growthPercent', 'unitVolume', 'asOf'}
    if not isinstance(data, dict) or set(data) != fields or not isinstance(public_id, str) or not re.fullmatch(r'[a-f0-9]{32,64}', public_id):
        return None
    name, date = data['displayName'], data['asOf']
    if type(data['schemaVersion']) is not int or data['schemaVersion'] != 1 or data['source'] != 'broker_verified' or data['isServerVerified'] is not True:
        return None
    if not isinstance(name, str) or not name.strip() or len(name) > 80 or '@' in name:
        return None
    if not isinstance(date, datetime) or date.tzinfo is None or date > now or now - date > timedelta(days=2):
        return None
    try:
        growth, volume = data['growthPercent'], data['unitVolume']
        if type(growth) not in (int, float) or type(volume) not in (int, float) or not math.isfinite(growth) or not math.isfinite(volume) or volume < 0:
            return None
    except (OverflowError, ValueError):
        return None
    return {**data, 'displayName': name.strip(), 'asOf': date.isoformat(), 'publicId': public_id}
