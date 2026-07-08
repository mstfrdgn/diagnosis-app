from __future__ import annotations

from typing import Optional, Union

from pydantic import BaseModel


class PredictRequest(BaseModel):
    values: dict[str, Union[str, float, None]]


class PredictResponse(BaseModel):
    predicted_class: str
    probabilities: dict[str, float]
