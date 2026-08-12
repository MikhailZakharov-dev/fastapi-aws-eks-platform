from pydantic import BaseModel, ConfigDict


class HealthResponse(BaseModel):
    status: str
    commit_sha: str


class TalkResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    speaker: str
