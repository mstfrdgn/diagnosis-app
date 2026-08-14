from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel


class VariableInfo(BaseModel):
    name: str
    type: Literal["continuous", "discrete", "string", "time"]
    role: Literal["feature", "class"]
    values: Optional[list[str]] = None   # discrete only
    min: Optional[float] = None          # continuous hint, if available in variable metadata
    max: Optional[float] = None


class DomainResponse(BaseModel):
    features: list[VariableInfo]
    class_var: VariableInfo
    # Class name of the pickled classifier (e.g. "TreeModel"), used by the
    # frontend to describe the model. None only if it cannot be determined.
    model_type: Optional[str] = None
