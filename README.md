# jw-library-read-api

FastAPI service to manage article reading status by `article_id`.

## What this API does

- Tracks article status with these values only:
  - `to_read`
  - `reading`
  - `read`
- Auto-creates missing IDs on first `GET` with default `to_read`
- Supports upsert writes via `PUT`
- Persists data in SQLite

## API contract

### `GET /articles/{article_id}/status`

- Returns `200` with current status.
- If `article_id` does not exist yet, it is created automatically with `to_read`.

Response:

```json
{
  "article_id": "abc-123",
  "status": "to_read"
}
```

### `PUT /articles/{article_id}/status`

- Upserts status for new or existing IDs.
- Allowed values: `to_read`, `reading`, `read`.
- Invalid values return `422`.

Request:

```json
{
  "status": "reading"
}
```

Response:

```json
{
  "article_id": "abc-123",
  "status": "reading"
}
```

## Local run (Python)

### Prerequisites

- Python 3.11+

### Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Start server

```bash
uvicorn app.main:app --reload
```

- API base URL: `http://127.0.0.1:8000`
- OpenAPI docs: `http://127.0.0.1:8000/docs`

### Environment variables

- `DATABASE_URL` (optional)
  - Default: `sqlite:///./data/read_status.db`

Example:

```bash
export DATABASE_URL="sqlite:///./data/read_status.db"
```

### Local usage example

```bash
curl -X PUT "http://127.0.0.1:8000/articles/abc-123/status" \
  -H "Content-Type: application/json" \
  -d '{"status":"reading"}'

curl "http://127.0.0.1:8000/articles/abc-123/status"
```

### Run tests

```bash
python -m pytest
```

## Docker

### Run with Compose

```bash
docker compose up --build
```

- API base URL: `http://127.0.0.1:8000`
- SQLite persistence volume: `read-status-data` mounted at `/app/data`

## Kubernetes (default namespace)

All manifests are under `k8s/`, one resource per YAML file:

- `k8s/configmap.yaml`
- `k8s/pv.yaml`
- `k8s/pvc.yaml`
- `k8s/deployment.yaml`
- `k8s/service.yaml`
- `k8s/ingress.yaml`
- `k8s/kong-plugin-key-auth.yaml`
- `k8s/kong-consumer.yaml`

Ingress style follows `jw-alpha-api` conventions:

- Ingress class: `kong`
- Annotation: `konghq.com/strip-path: "true"`
- Host: `api.massaini.xyz`
- Path prefix: `/jw-library-read-api`

### Deploy script

```bash
./build_and_deploy.sh
```

What it does:

- Builds and pushes the Docker image
- Applies all Kubernetes manifests
- Updates deployment image and waits for rollout
- Runs API key setup by default

Useful overrides:

```bash
DOCKER_REPOSITORY=your-user IMAGE_TAG=v1 ./build_and_deploy.sh
DOCKER_PLATFORM=linux/arm64 ./build_and_deploy.sh
RUN_API_KEY_SETUP=false ./build_and_deploy.sh
```

### API key setup script (Kong key-auth)

```bash
./generate_api_key.sh
```

What it does:

- Applies Kong plugin and consumer manifests
- Creates secret `jw-library-read-api-key-auth-cred` if missing
- Saves generated key to `.apikey` (on create/rotation)
- Annotates service with plugin

Rotate key:

```bash
FORCE_REGENERATE=true ./generate_api_key.sh
```

If secret already exists, the script keeps it and does not print the key again.

Read current key from Kubernetes:

```bash
kubectl -n default get secret jw-library-read-api-key-auth-cred -o jsonpath='{.data.key}' | openssl base64 -d -A; echo
```

If available locally:

```bash
cat .apikey
```

### Ingress request example

```bash
API_KEY="$(kubectl -n default get secret jw-library-read-api-key-auth-cred -o jsonpath='{.data.key}' | openssl base64 -d -A)"

curl "https://api.massaini.xyz/jw-library-read-api/articles/abc-123/status" \
  -H "apikey: ${API_KEY}"
```

## Storage note

`k8s/pv.yaml` uses this hostPath:

- `/Users/temporaryadmin/JwLibraryReadApi`

Update it if your Kubernetes node path is different.

## Troubleshooting

- `401 Unauthorized` through ingress:
  - Ensure `apikey` header is sent
  - Ensure service annotation includes plugin:
    - `kubectl -n default get service jw-library-read-api -o yaml | rg konghq.com/plugins`
- Could not retrieve key from `.apikey`:
  - Secret may already exist from earlier runs; fetch from Kubernetes instead.
- Pod not becoming ready:
  - Check rollout and logs:
    - `kubectl -n default rollout status deployment/jw-library-read-api`
    - `kubectl -n default logs deployment/jw-library-read-api`
