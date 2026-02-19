FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential libffi-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download embedding model at build time (so startup is instant)
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('nomic-ai/nomic-embed-text-v1.5', trust_remote_code=True)"

COPY . .

EXPOSE 8100
VOLUME /data

ENV EMBEDDING_MODEL=nomic-ai/nomic-embed-text-v1.5
ENV LANCEDB_PATH=/data/lancedb
ENV UPLOAD_PATH=/data/uploads
ENV PORT=8100

CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8100"]
