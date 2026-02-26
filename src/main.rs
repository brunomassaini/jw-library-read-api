use std::env;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool, sqlite::SqlitePoolOptions};

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
#[serde(rename_all = "snake_case")]
enum Status {
    ToRead,
    Reading,
    Read,
}

impl Status {
    fn as_str(&self) -> &'static str {
        match self {
            Status::ToRead => "to_read",
            Status::Reading => "reading",
            Status::Read => "read",
        }
    }

    fn from_str(s: &str) -> Option<Self> {
        match s {
            "to_read" => Some(Status::ToRead),
            "reading" => Some(Status::Reading),
            "read" => Some(Status::Read),
            _ => None,
        }
    }
}

#[derive(Serialize, Deserialize)]
struct StatusResponse {
    article_id: String,
    status: Status,
}

#[derive(Deserialize)]
struct StatusUpsertRequest {
    status: Status,
}

async fn get_article_status(
    State(pool): State<SqlitePool>,
    Path(article_id): Path<String>,
) -> Result<Json<StatusResponse>, StatusCode> {
    let row = sqlx::query("SELECT status FROM reading_status WHERE article_id = ?")
        .bind(&article_id)
        .fetch_optional(&pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let status = match row {
        Some(r) => {
            let s: String = r.get("status");
            Status::from_str(&s).ok_or(StatusCode::INTERNAL_SERVER_ERROR)?
        }
        None => {
            let now = Utc::now().to_rfc3339();
            sqlx::query(
                "INSERT INTO reading_status (article_id, status, created_at, updated_at) VALUES (?, ?, ?, ?)",
            )
            .bind(&article_id)
            .bind("to_read")
            .bind(&now)
            .bind(&now)
            .execute(&pool)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            Status::ToRead
        }
    };

    Ok(Json(StatusResponse { article_id, status }))
}

async fn put_article_status(
    State(pool): State<SqlitePool>,
    Path(article_id): Path<String>,
    Json(payload): Json<StatusUpsertRequest>,
) -> Result<Json<StatusResponse>, StatusCode> {
    let now = Utc::now().to_rfc3339();
    let status_str = payload.status.as_str();

    sqlx::query(
        "INSERT INTO reading_status (article_id, status, created_at, updated_at) \
         VALUES (?, ?, ?, ?) \
         ON CONFLICT(article_id) DO UPDATE SET status = excluded.status, updated_at = excluded.updated_at",
    )
    .bind(&article_id)
    .bind(status_str)
    .bind(&now)
    .bind(&now)
    .execute(&pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(StatusResponse {
        article_id,
        status: payload.status,
    }))
}

async fn get_openapi() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "openapi": "3.0.3",
        "info": {
            "title": "JW Library Read API",
            "version": "1.0.0"
        },
        "paths": {
            "/articles/{article_id}/status": {
                "get": {
                    "operationId": "get_article_status",
                    "parameters": [{
                        "name": "article_id",
                        "in": "path",
                        "required": true,
                        "schema": { "type": "string" }
                    }],
                    "responses": {
                        "200": {
                            "description": "Article reading status",
                            "content": {
                                "application/json": {
                                    "schema": { "$ref": "#/components/schemas/StatusResponse" }
                                }
                            }
                        }
                    }
                },
                "put": {
                    "operationId": "put_article_status",
                    "parameters": [{
                        "name": "article_id",
                        "in": "path",
                        "required": true,
                        "schema": { "type": "string" }
                    }],
                    "requestBody": {
                        "required": true,
                        "content": {
                            "application/json": {
                                "schema": { "$ref": "#/components/schemas/StatusUpsertRequest" }
                            }
                        }
                    },
                    "responses": {
                        "200": {
                            "description": "Updated article reading status",
                            "content": {
                                "application/json": {
                                    "schema": { "$ref": "#/components/schemas/StatusResponse" }
                                }
                            }
                        }
                    }
                }
            }
        },
        "components": {
            "schemas": {
                "Status": {
                    "type": "string",
                    "enum": ["to_read", "reading", "read"]
                },
                "StatusResponse": {
                    "type": "object",
                    "required": ["article_id", "status"],
                    "properties": {
                        "article_id": { "type": "string" },
                        "status": { "$ref": "#/components/schemas/Status" }
                    }
                },
                "StatusUpsertRequest": {
                    "type": "object",
                    "required": ["status"],
                    "properties": {
                        "status": { "$ref": "#/components/schemas/Status" }
                    }
                }
            }
        }
    }))
}

fn normalize_database_url(url: &str) -> String {
    // Convert SQLAlchemy sqlite:///./path to sqlx-compatible sqlite:./path
    if let Some(path) = url.strip_prefix("sqlite:///") {
        format!("sqlite:{}", path)
    } else {
        url.to_string()
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let raw_url = env::var("DATABASE_URL")
        .unwrap_or_else(|_| "sqlite:///./data/read_status.db".to_string());
    let database_url = normalize_database_url(&raw_url);

    // Ensure the data directory exists for SQLite file databases
    if database_url.starts_with("sqlite:") && !database_url.contains(":memory:") {
        let file_path = database_url.trim_start_matches("sqlite:");
        if let Some(parent) = std::path::Path::new(file_path).parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).expect("Failed to create database directory");
            }
        }
    }

    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Failed to connect to SQLite database");

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS reading_status (
            article_id TEXT PRIMARY KEY,
            status TEXT NOT NULL CHECK(status IN ('to_read', 'reading', 'read')),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )",
    )
    .execute(&pool)
    .await
    .expect("Failed to initialize database schema");

    let app = Router::new()
        .route(
            "/articles/:article_id/status",
            get(get_article_status).put(put_article_status),
        )
        .route("/openapi.json", get(get_openapi))
        .with_state(pool);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8000")
        .await
        .expect("Failed to bind to port 8000");

    tracing::info!("Server listening on 0.0.0.0:8000");
    axum::serve(listener, app).await.unwrap();
}
