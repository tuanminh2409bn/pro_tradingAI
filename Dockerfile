# Verified official Python 3.12 image; the bootstrap preserves Docker seccomp.
ARG PYTHON_RUNTIME_IMAGE=python:3.12.15-slim-bookworm@sha256:54c85f3c47607a77f32adec749d3c81d1348bf25833671f512b26a9b6d778cb3
FROM ${PYTHON_RUNTIME_IMAGE}

COPY deploy/runtime_seccomp.py /usr/local/bin/runtime_seccomp.py
# Keep Docker's filter; deny newer syscalls with errno for glibc fallback.
SHELL ["python", "/usr/local/bin/runtime_seccomp.py", "/bin/sh", "-c"]

# Cài đặt các công cụ hệ thống
RUN apt-get update && apt-get install -y \
    build-essential \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
COPY deploy/backend-production-constraints.txt .
RUN pip install --no-cache-dir -r requirements.txt -c backend-production-constraints.txt
RUN pip check

COPY server.py .
COPY feature_engine.py .
COPY analysis_cache.py .
COPY analysis_contract.py .
COPY admin_controls.py .
COPY entitlements.py .
COPY observability.py .
COPY trade_gate.py .
COPY daily_loss_guard.py .
COPY cutoff_state.py .
COPY http_boundary.py .
COPY market_history.py .
COPY oanda_history.py .
COPY tradingview_history.py .
COPY market_sessions.py .
COPY push_preferences.py .
COPY specialist_analysis.py .
COPY analysis_pipeline.py .
COPY quota_store.py .
COPY backtest_api.py .
COPY community_api.py .
COPY referral_api.py .
COPY referral_ledger.py .
COPY official_news.py .

# Không ép cứng cổng ở đây, Google Cloud sẽ cấp biến môi trường PORT
ENTRYPOINT ["python", "/usr/local/bin/runtime_seccomp.py"]
CMD uvicorn server:app --host 0.0.0.0 --port ${PORT:-8000}
