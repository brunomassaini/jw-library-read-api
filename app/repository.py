from datetime import datetime, timezone

from sqlalchemy.orm import Session

from .models import ReadingStatus
from .schemas import StatusEnum


def get_status(session: Session, article_id: str) -> ReadingStatus | None:
    return session.get(ReadingStatus, article_id)


def upsert_status(session: Session, article_id: str, status: StatusEnum) -> ReadingStatus:
    record = session.get(ReadingStatus, article_id)

    if record is None:
        record = ReadingStatus(article_id=article_id, status=status.value)
        session.add(record)
    else:
        record.status = status.value
        record.updated_at = datetime.now(timezone.utc)

    session.commit()
    session.refresh(record)
    return record
