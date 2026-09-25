FROM python:3.10-slim-bullseye

# Cài đặt các công cụ hệ thống
RUN apt-get update && apt-get install -y \
    build-essential \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

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
COPY push_preferences.py .

# Không ép cứng cổng ở đây, Google Cloud sẽ cấp biến môi trường PORT
CMD uvicorn server:app --host 0.0.0.0 --port ${PORT:-8000}
