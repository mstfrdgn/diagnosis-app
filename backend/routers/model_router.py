from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from schemas.domain_schema import DomainResponse
from services.model_service import ModelNotLoadedError, model_service

router = APIRouter()


class LoadModelRequest(BaseModel):
    path: str


class ModelStatus(BaseModel):
    loaded: bool
    path: Optional[str] = None


@router.post("/load", response_model=DomainResponse)
def load_model(request: LoadModelRequest) -> DomainResponse:
    """Load a .pkcls model file and return its domain."""
    try:
        model_service.load(request.path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Failed to load model: {exc}")
    return model_service.get_domain_response()


@router.get("/domain", response_model=DomainResponse)
def get_domain() -> DomainResponse:
    """Return the domain of the currently loaded model."""
    try:
        return model_service.get_domain_response()
    except ModelNotLoadedError:
        raise HTTPException(status_code=404, detail="No model is loaded.")


@router.get("/status", response_model=ModelStatus)
def get_status() -> ModelStatus:
    """Return whether a model is loaded and its file path."""
    return ModelStatus(loaded=model_service.is_loaded(), path=model_service.path)
