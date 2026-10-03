"""Real Auth-token and Firestore Rules role matrix, local Emulators only."""

import json
import os
import re
import secrets
import unittest
import urllib.error
import urllib.request
import uuid


PROJECT = "protrading-ai-2026"
AUTH_HOST = os.environ.get("FIREBASE_AUTH_EMULATOR_HOST", "")
FIRESTORE_HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "")
LOCAL_HOST = r"(?:127\.0\.0\.1|localhost):[0-9]+"


def _request_status(url, *, method="GET", payload=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode() if payload is not None else None,
        method=method,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            body = response.read()
            return response.status, json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        return status, None


@unittest.skipUnless(
    re.fullmatch(LOCAL_HOST, AUTH_HOST) and re.fullmatch(LOCAL_HOST, FIRESTORE_HOST),
    "requires loopback Auth and Firestore Emulators",
)
class AuthRoleEmulatorTests(unittest.TestCase):
    def test_real_id_tokens_enforce_admin_role_matrix(self):
        import firebase_admin
        from firebase_admin import auth

        app = firebase_admin.initialize_app(
            options={"projectId": PROJECT}, name=f"role-matrix-{uuid.uuid4().hex}"
        )
        document = (
            f"http://{FIRESTORE_HOST}/v1/projects/{PROJECT}/databases/"
            f"(default)/documents/admin/role-matrix-{uuid.uuid4().hex}"
        )
        self.assertEqual(
            _request_status(
                document,
                method="PATCH",
                payload={"fields": {"value": {"integerValue": "1"}}},
                token="owner",
            )[0],
            200,
        )
        created_users = []
        try:
            for role, is_admin in (
                ("standard", False),
                ("verified_partner", False),
                ("professional", False),
                ("enterprise", False),
                ("reserved_fifth", False),
                ("reserved_fifth", True),
                ("undefined", True),
                (None, True),
                ("standard", True),
            ):
                uid = f"qa-{uuid.uuid4().hex}"
                email = f"{uid}@example.test"
                password = secrets.token_urlsafe(18)
                auth.create_user(uid=uid, email=email, password=password, app=app)
                created_users.append(uid)
                claims = {"role": role} if role is not None else {}
                if is_admin:
                    claims["admin"] = True
                auth.set_custom_user_claims(uid, claims, app=app)
                status, sign_in = _request_status(
                    f"http://{AUTH_HOST}/identitytoolkit.googleapis.com/v1/"
                    "accounts:signInWithPassword?key=local-test",
                    method="POST",
                    payload={
                        "email": email,
                        "password": password,
                        "returnSecureToken": True,
                    },
                )
                with self.subTest(role=role, admin=is_admin):
                    self.assertEqual(status, 200)
                    token = sign_in["idToken"]
                    expected = 200 if is_admin and role == "standard" else 403
                    self.assertEqual(_request_status(document, token=token)[0], expected)
                    self.assertEqual(
                        _request_status(
                            document,
                            method="PATCH",
                            payload={"fields": {"value": {"integerValue": "2"}}},
                            token=token,
                        )[0],
                        expected,
                    )
        finally:
            _request_status(document, method="DELETE", token="owner")
            for uid in created_users:
                auth.delete_user(uid, app=app)
            firebase_admin.delete_app(app)


if __name__ == "__main__":
    unittest.main()
