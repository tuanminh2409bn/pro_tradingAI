"""Pure validation and opaque, owner-bound IDs for Community writes."""

import hashlib
import json
import re


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
