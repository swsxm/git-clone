from typing import Any

from pydantic import BaseModel, StrictStr, model_validator


class GitUrl(BaseModel):
    """
    Data model for a parsed Git URL.
    """

    proto: StrictStr
    host: StrictStr
    repo: StrictStr

    @model_validator(mode="before")
    def validate_not_empty(cls, values: dict[str, Any]) -> dict[str, Any]:
        if not all(values.get(field) for field in ("proto", "host", "repo")):
            raise ValueError("`proto`, `host`, and `repo` must be non-empty strings")
        return values
