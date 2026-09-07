# Redis for Day 3 analysis cache

Ubuntu 16 system Redis (3.x) is **too old** for `redis-py` 5+ (`HELLO` / RESP3). Use **Redis 7** container:

```bash
docker run -d --name protrading-redis --restart unless-stopped --network host \
  redis:7-alpine redis-server --bind 127.0.0.1 --port 6380
```

App container (host network):

```bash
docker run -d --name protrading-ai --restart unless-stopped --network host \
  -e REDIS_URL=redis://127.0.0.1:6380/0 \
  -e DEEPSEEK_API_KEY=... \
  -v /opt/protrading-ai/firebase-adminsdk.json:/app/firebase-adminsdk.json:ro \
  protrading-ai
```

Health should show `"analysis_cache":"redis"`. If unset/unreachable → in-memory fallback (single worker).
