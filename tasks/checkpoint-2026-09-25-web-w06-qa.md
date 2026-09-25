# Web W06 local QA checkpoint — 2026-09-25

This is local Auth/Firestore Emulator evidence on the uncommitted working tree.
No production Firebase account, provider account, Rules deployment or backend
cutover was created. QA identities and fixture data existed only in the local
Emulators; no QA password or ID token is stored in this repository.
The earlier loopback VPS backend candidate was not updated with this W06 work.

## Change and risk boundary

- A Web build with `PROTRADING_USE_FIREBASE_EMULATORS=true` connects Firebase
  Auth to `127.0.0.1:9099` and Firestore to `127.0.0.1:8080` before repositories
  or BLoCs are constructed. The default build stays on configured Firebase.
- Google sign-in is hidden and not initialized in local QA mode. The QA Web
  build pointed API/WebSocket at an unused loopback port, preventing accidental
  calls to the public backend during the role browser check.
- Admin now requires both the exact `admin=true` claim and a defined account
  role: Standard, Verified Partner, Professional or Enterprise. Missing,
  unknown and `reserved_fifth` roles fail closed in the Web gate, Firestore
  Rules and Python Admin contract. Existing production Admin claims must be
  audited for a defined role before these local Rules are deployed.

## Reproduce locally

Use the Android Studio bundled JBR if `java -version` cannot find a runtime:

```sh
env PATH="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin:$PATH" \
  firebase emulators:start --only auth,firestore \
  --project protrading-ai-2026 --non-interactive
```

In another terminal, build an isolated Web client and serve it:

```sh
flutter build web --release --no-pub \
  --dart-define=PROTRADING_USE_FIREBASE_EMULATORS=true \
  --dart-define=PROTRADING_API_BASE_URL=http://127.0.0.1:8999 \
  --dart-define=PROTRADING_WS_BASE_URL=ws://127.0.0.1:8999
python3 -m http.server 8082 --bind 127.0.0.1 --directory build/web
```

Port 8999 is intentionally closed for this auth-only QA build. Do not treat
its Trading Room unavailable state as evidence for the market/backend flows.
The browser smoke used `http://127.0.0.1:8082/`; using a fresh origin avoided
a stale Flutter service-worker cache from an earlier test build.

To create three disposable browser QA users, run this in an environment with
the existing `firebase-admin` dependency. The prompt reads one local password
without writing it to a file or command history:

```sh
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
GCLOUD_PROJECT=protrading-ai-2026 python3 - <<'PY'
import getpass
import os
import firebase_admin
from firebase_admin import auth

assert os.environ['FIREBASE_AUTH_EMULATOR_HOST'] == '127.0.0.1:9099'
app = firebase_admin.initialize_app(options={'projectId': 'protrading-ai-2026'})
password = getpass.getpass('Disposable QA password: ')
if len(password) < 8:
    raise SystemExit('Use at least 8 characters')
for name, claims in (
    ('standard', {'role': 'standard'}),
    ('admin', {'role': 'standard', 'admin': True}),
    ('reserved', {'role': 'reserved_fifth', 'admin': True}),
):
    uid = f'qa-{name}-local'
    email = f'qa-{name}@example.test'
    try:
        auth.get_user(uid, app=app)
    except auth.UserNotFoundError:
        auth.create_user(uid=uid, email=email, password=password, app=app)
    else:
        auth.update_user(uid, email=email, password=password, app=app)
    auth.set_custom_user_claims(uid, claims, app=app)
    print(f'Emulator user ready: {email}')
PY
```

## Evidence

- Python discovery with both Emulator hosts and the existing temporary QA
  dependency environment: **214/214 passed**, no skips. This includes 23
  Auth/Firestore Emulator cases. `test_v21_auth_role_emulator.py` signs in with
  real local ID tokens and checks Admin read/write across the four enabled
  roles, `reserved_fifth`, an unknown role and a missing role.
- Flutter: **119/119 passed**. The Admin widget gate covers denied roles and
  an allowed Admin claim. Analyzer exited 0 with zero errors/warnings and three
  pre-existing Mobile `activeColor` deprecation infos.
- Flutter Web QA release build passed. `main.dart.js` SHA-256:
  `370c76799b138a8efd91abc9ea5e2095926027a32b932341b05d61b7726518e6`.
  `git diff --check` passed.
- Browser: a local Standard account had no Admin Center entry. An Admin account
  with `role=standard` opened Admin Center and its live stats changed after a
  fixture write to `admin/stats` in Firestore Emulator. A `reserved_fifth`
  account carrying `admin=true` could log in but had no Admin Center entry.

W06's UI and Firestore boundaries have direct local evidence. The remaining
W06/W30 release work is to audit existing Admin claims, test any future
Admin-mutation HTTP routes when they are wired, and repeat the role matrix on
the eventual staging build. This checkpoint does not mark other Web tabs PASS.
