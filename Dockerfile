FROM python:3.10-slim

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

# Không ép cứng cổng ở đây, Google Cloud sẽ cấp biến môi trường PORT
CMD uvicorn server:app --host 0.0.0.0 --port ${PORT:-8000}
