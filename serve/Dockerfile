# N-ATLaS gateway — local/self-hosted GPU deployment.
# For Modal, use serve/modal_app.py instead; this is the Docker Compose path.

FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/model-cache

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.11 \
        python3-pip \
        ffmpeg \
        curl \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3.11 /usr/bin/python

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8000

CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000"]
