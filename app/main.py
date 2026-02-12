from fastapi import Depends, FastAPI
from sqlalchemy.orm import Session

from .db import get_db, init_db
from .repository import get_status, upsert_status
from .schemas import StatusEnum, StatusResponse, StatusUpsertRequest

app = FastAPI(title="JW Library Read API")


@app.on_event("startup")
def on_startup() -> None:
    init_db()


@app.get("/articles/{article_id}/status", response_model=StatusResponse)
def get_article_status(article_id: str, db: Session = Depends(get_db)) -> StatusResponse:
    status_record = get_status(db, article_id)
    if status_record is None:
        status_record = upsert_status(db, article_id, StatusEnum.to_read)

    return StatusResponse(article_id=status_record.article_id, status=status_record.status)


@app.put("/articles/{article_id}/status", response_model=StatusResponse)
def put_article_status(
    article_id: str,
    payload: StatusUpsertRequest,
    db: Session = Depends(get_db),
) -> StatusResponse:
    status_record = upsert_status(db, article_id, payload.status)
    return StatusResponse(article_id=status_record.article_id, status=status_record.status)
