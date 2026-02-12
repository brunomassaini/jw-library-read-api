from collections.abc import Generator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app import models  # noqa: F401
from app.db import Base, get_db
from app.main import app


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Generator[TestClient, None, None]:
    database_url = f"sqlite:///{tmp_path / 'test.db'}"
    engine = create_engine(database_url, connect_args={"check_same_thread": False})
    testing_session_local = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    Base.metadata.create_all(bind=engine)

    def override_get_db() -> Generator[Session, None, None]:
        db = testing_session_local()
        try:
            yield db
        finally:
            db.close()

    monkeypatch.setattr("app.main.init_db", lambda: None)
    app.dependency_overrides[get_db] = override_get_db

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)
    engine.dispose()


def test_get_unknown_article_creates_to_read_status(client: TestClient) -> None:
    response = client.get("/articles/missing-article/status")
    assert response.status_code == 200
    assert response.json() == {"article_id": "missing-article", "status": "to_read"}

    second_response = client.get("/articles/missing-article/status")
    assert second_response.status_code == 200
    assert second_response.json() == {"article_id": "missing-article", "status": "to_read"}


@pytest.mark.parametrize("status", ["to_read", "reading", "read"])
def test_put_creates_article_and_get_returns_persisted_value(
    client: TestClient, status: str
) -> None:
    article_id = f"article-{status}"

    put_response = client.put(f"/articles/{article_id}/status", json={"status": status})
    assert put_response.status_code == 200
    assert put_response.json() == {"article_id": article_id, "status": status}

    get_response = client.get(f"/articles/{article_id}/status")
    assert get_response.status_code == 200
    assert get_response.json() == {"article_id": article_id, "status": status}


def test_put_updates_existing_article_status(client: TestClient) -> None:
    article_id = "article-update"

    first_response = client.put(f"/articles/{article_id}/status", json={"status": "to_read"})
    assert first_response.status_code == 200

    second_response = client.put(f"/articles/{article_id}/status", json={"status": "read"})
    assert second_response.status_code == 200
    assert second_response.json() == {"article_id": article_id, "status": "read"}

    get_response = client.get(f"/articles/{article_id}/status")
    assert get_response.status_code == 200
    assert get_response.json() == {"article_id": article_id, "status": "read"}


def test_put_invalid_status_returns_422(client: TestClient) -> None:
    response = client.put("/articles/article-invalid/status", json={"status": "invalid_status"})

    assert response.status_code == 422


def test_multiple_article_statuses_are_isolated(client: TestClient) -> None:
    response_a = client.put("/articles/article-a/status", json={"status": "to_read"})
    response_b = client.put("/articles/article-b/status", json={"status": "reading"})

    assert response_a.status_code == 200
    assert response_b.status_code == 200

    get_a = client.get("/articles/article-a/status")
    get_b = client.get("/articles/article-b/status")

    assert get_a.status_code == 200
    assert get_b.status_code == 200
    assert get_a.json()["status"] == "to_read"
    assert get_b.json()["status"] == "reading"


def test_openapi_exposes_allowed_status_enum(client: TestClient) -> None:
    response = client.get("/openapi.json")
    assert response.status_code == 200

    openapi = response.json()
    enum_values = openapi["components"]["schemas"]["StatusEnum"]["enum"]
    assert set(enum_values) == {"to_read", "reading", "read"}
