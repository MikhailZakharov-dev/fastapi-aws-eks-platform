from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: str
    commit_sha: str
