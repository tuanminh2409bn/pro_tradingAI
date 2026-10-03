"""CORS and external image boundary tests."""

import unittest
from unittest.mock import patch

from http_boundary import (
    DEFAULT_WEB_ORIGINS,
    UnsafeExternalUrl,
    all_addresses_are_public,
    validate_public_https_url,
    web_allowed_origins,
)


class HttpBoundaryTests(unittest.IsolatedAsyncioTestCase):
    def test_default_and_configured_origins_are_explicit(self):
        self.assertEqual(web_allowed_origins(""), DEFAULT_WEB_ORIGINS)
        self.assertEqual(
            web_allowed_origins("https://trade.example.com,http://localhost:5000/"),
            ("https://trade.example.com", "http://localhost:5000"),
        )
        for invalid in (
            "*", "http://trade.example.com", "https://trade.example.com/path",
            "https://trade.example.com:bad", "https://trade.example.com:99999",
            "https://trade.example.com:0",
        ):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                web_allowed_origins(invalid)

    def test_private_reserved_or_empty_dns_results_fail(self):
        self.assertFalse(all_addresses_are_public([]))
        self.assertFalse(all_addresses_are_public(["127.0.0.1"]))
        self.assertFalse(all_addresses_are_public(["169.254.169.254"]))
        self.assertFalse(all_addresses_are_public(["10.0.0.1", "8.8.8.8"]))
        self.assertTrue(all_addresses_are_public(["8.8.8.8", "1.1.1.1"]))

    async def test_proxy_url_requires_https_and_public_dns(self):
        with self.assertRaises(UnsafeExternalUrl):
            await validate_public_https_url("http://example.com/image.png")
        with self.assertRaises(UnsafeExternalUrl):
            await validate_public_https_url("https://user:pass@example.com/image.png")
        for invalid in (
            "https://cdn.example.com:bad/image.png",
            "https://cdn.example.com:99999/image.png",
            "https://cdn.example.com:0/image.png",
        ):
            with self.subTest(invalid=invalid), self.assertRaises(UnsafeExternalUrl):
                await validate_public_https_url(invalid)

        public_answer = [(2, 1, 6, "", ("8.8.8.8", 443))]
        with patch.dict("http_boundary.os.environ", {"IMAGE_PROXY_ALLOWED_HOSTS": "cdn.example.com"}):
            with patch("http_boundary.socket.getaddrinfo", return_value=public_answer):
                self.assertEqual(
                    await validate_public_https_url("https://cdn.example.com/image.png"),
                    "https://cdn.example.com/image.png",
                )
            for unapproved in (
                "https://other.example.com/image.png",
                "https://cdn.example.com.attacker.test/image.png",
            ):
                with self.subTest(unapproved=unapproved), self.assertRaises(UnsafeExternalUrl):
                    await validate_public_https_url(unapproved)

        with patch.dict("http_boundary.os.environ", {"IMAGE_PROXY_ALLOWED_HOSTS": ""}):
            with patch("http_boundary.socket.getaddrinfo") as lookup:
                with self.assertRaises(UnsafeExternalUrl):
                    await validate_public_https_url("https://cdn.example.com/image.png")
                lookup.assert_not_called()

        private_answer = [(2, 1, 6, "", ("127.0.0.1", 443))]
        with patch.dict("http_boundary.os.environ", {"IMAGE_PROXY_ALLOWED_HOSTS": "internal.example"}):
            with patch("http_boundary.socket.getaddrinfo", return_value=private_answer):
                with self.assertRaises(UnsafeExternalUrl):
                    await validate_public_https_url("https://internal.example/image.png")


if __name__ == "__main__":
    unittest.main()
