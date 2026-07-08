from __future__ import annotations

from fastapi import APIRouter, HTTPException

from schemas.predict_schema import PredictRequest, PredictResponse
from services.model_service import ModelNotLoadedError, model_service

router = APIRouter()


@router.post("/predict", response_model=PredictResponse)
def predict(request: PredictRequest) -> PredictResponse:
    """Run the loaded model on the supplied feature values."""
    try:
        predicted_class, probabilities = model_service.predict(request.values)
    except ModelNotLoadedError:
        raise HTTPException(status_code=404, detail="No model is loaded.")
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Prediction failed: {exc}")
    return PredictResponse(predicted_class=predicted_class, probabilities=probabilities)
