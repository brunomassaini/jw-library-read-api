from datetime import datetime, timezone

from sqlalchemy import CheckConstraint, Column, DateTime, String

from .db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ReadingStatus(Base):
    __tablename__ = "reading_status"
    __table_args__ = (
        CheckConstraint(
            "status in ('to_read', 'reading', 'read')",
            name="ck_reading_status_status",
        ),
    )

    article_id = Column(String, primary_key=True)
    status = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utcnow)
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=utcnow,
        onupdate=utcnow,
    )
