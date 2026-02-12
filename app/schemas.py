from enum import Enum

from pydantic import BaseModel, ConfigDict


class StatusEnum(str, Enum):
    to_read = "to_read"
    reading = "reading"
    read = "read"


class StatusUpsertRequest(BaseModel):
    status: StatusEnum


class StatusResponse(BaseModel):
    article_id: str
    status: StatusEnum

    model_config = ConfigDict(from_attributes=True)
