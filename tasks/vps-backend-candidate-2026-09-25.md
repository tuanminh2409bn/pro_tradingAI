# VPS backend candidate — 2026-09-25

This records the user's VPS address and the isolated backend deployed for local
Web testing. It contains no password, key, token or service-account contents.
The current production backend, Nginx and Redis were not replaced or restarted.

## Access and build identity

- VPS address supplied by user: `103.69.189.243`; SSH user: `root`.
- Hostname supplied by user: `server.6013248957` (DNS not verified). The public
  backend currently answers at `https://103-69-189-243.sslip.io`.
- Candidate source manifest SHA-256:
  `fcf1fe88066aeb2c1d7ee143219b326348a873055dd543e6a0474c00d69c1345`.
- Candidate source directory on VPS:
  `/opt/protrading-ai-candidates/fcf1fe88066a`.
- Docker image `protrading-ai:fcf1fe88066a`, image ID
  `sha256:9d966a014abe62489de80927b9b053cc0942a0519fc15330f7796ffdedcbcb9b`.
- Running container `protrading-ai-candidate-fcf1fe88066a` listens on VPS
  loopback `127.0.0.1:8001`; Docker restart policy is `no`.
- The production container `protrading-ai` remains on `protrading-ai:latest`
  and continues to serve the public endpoint.

## How to test locally

With authorized SSH access, forward local port 8001 to VPS loopback:

```sh
ssh -N -L 127.0.0.1:8001:127.0.0.1:8001 root@103.69.189.243
```

In a separate terminal, build and serve the Web client against the candidate:

```sh
flutter build web --release --no-pub \
  --dart-define=PROTRADING_API_BASE_URL=http://127.0.0.1:8001 \
  --dart-define=PROTRADING_WS_BASE_URL=ws://127.0.0.1:8001
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8080/`. These two build definitions affect this local
Web build only; the client defaults still point at the existing public backend.
The candidate runs `uvicorn server:app --host 127.0.0.1 --port 8001
--lifespan off`, so background workers do not run against production Firestore.
It has no DeepSeek or Redis environment configuration. Authenticated API calls
can still reach production Firebase data because the container has the existing
read-only service-account mount; use only an approved QA identity and dataset.

## Verified

- Candidate `/health` returned 200 through the SSH tunnel. Unauthenticated
  private endpoints returned 401; disallowed CORS preflight returned 400, local
  Web origin preflight returned 200.
- Local Web release build completed with the candidate URL. Login rendered in
  browser, EN/VI switched, and browser console had no warnings or errors.
- Python discovery: 212 tests, 21 Emulator-only skips. Flutter: 117/117 tests
  passed. Container import-contract regression passed, as did `git diff --check`.

The candidate is a backend packaging and unauthenticated smoke milestone. It
does not make the Web plan 100% complete. A licensed market/news provider,
claim-bearing QA user, safe test data, authenticated Web flow, background worker
and staged release checks are still required before production cutover.
