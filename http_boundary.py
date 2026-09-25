"""HTTP boundary policy for Web origins and external image fetching."""

from __future__ import annotations

import asyncio
import ipaddress
import os
import socket
from urllib.parse import urlparse


DEFAULT_WEB_ORIGINS = (
    "https://protrading-ai-2026.web.app",
    "https://protrading-ai-2026.firebaseapp.com",
    "http://localhost:5000",
    "http://localhost:8080",
)


class UnsafeExternalUrl(ValueError):
    pass


def web_allowed_origins(raw: str | None = None) -> tuple[str, ...]:
    """Return explicit browser origins; wildcards and origins with paths fail."""
    source = raw if raw is not None else os.environ.get("WEB_ALLOWED_ORIGINS", "")
    candidates = [item.strip().rstrip("/") for item in source.split(",") if item.strip()]
    if not candidates:
        return DEFAULT_WEB_ORIGINS
    validated: list[str] = []
    for candidate in candidates:
        try:
            parsed = urlparse(candidate)
            port = parsed.port
        except ValueError as error:
            raise ValueError("WEB_ALLOWED_ORIGINS contains an invalid origin") from error
        local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"}
        if (
            candidate == "*"
            or not parsed.hostname
            or port == 0
            or (parsed.scheme != "https" and not local_http)
            or parsed.username
            or parsed.password
            or parsed.path not in ("", "/")
            or parsed.params
            or parsed.query
            or parsed.fragment
        ):
            raise ValueError("WEB_ALLOWED_ORIGINS contains an invalid origin")
        if candidate not in validated:
            validated.append(candidate)
    return tuple(validated)


def all_addresses_are_public(addresses: list[str]) -> bool:
    if not addresses:
        return False
    try:
        return all(ipaddress.ip_address(address).is_global for address in addresses)
    except ValueError:
        return False


async def validate_public_https_url(raw: str) -> str:
    """Reject credentials, non-HTTPS schemes, and private/reserved DNS targets."""
    if not isinstance(raw, str) or len(raw) > 2048:
        raise UnsafeExternalUrl("Invalid external URL")
    try:
        parsed = urlparse(raw)
        port = parsed.port
    except ValueError as error:
        raise UnsafeExternalUrl("Invalid external URL") from error
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or port == 0
        or parsed.username
        or parsed.password
        or parsed.fragment
    ):
        raise UnsafeExternalUrl("Only public HTTPS image URLs are allowed")
    approved_hosts = {
        host.strip().lower()
        for host in os.environ.get("IMAGE_PROXY_ALLOWED_HOSTS", "").split(",")
        if host.strip()
    }
    if parsed.hostname.lower().rstrip(".") not in approved_hosts:
        raise UnsafeExternalUrl("External image host is not approved")
    try:
        results = await asyncio.to_thread(
            socket.getaddrinfo,
            parsed.hostname,
            port or 443,
            0,
            socket.SOCK_STREAM,
        )
    except OSError as error:
        raise UnsafeExternalUrl("External image host is unavailable") from error
    addresses = list({item[4][0] for item in results if item[4]})
    if not all_addresses_are_public(addresses):
        raise UnsafeExternalUrl("External image host is not public")
    return raw
