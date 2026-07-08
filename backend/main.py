from __future__ import annotations

import argparse

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import model_router, predict_router

app = FastAPI(title="Diagnostic App Backend", version="1.0.0")

# Allow all localhost origins so the Flutter HTTP client and any dev tools can reach us
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

app.include_router(model_router.router, prefix="/model", tags=["model"])
app.include_router(predict_router.router, tags=["predict"])


@app.get("/health", tags=["health"])
def health() -> dict:
    """Liveness probe polled by the Flutter app after process launch."""
    return {"status": "ok"}


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Diagnostic App backend")
    p.add_argument("--host", default="127.0.0.1", help="Bind host")
    p.add_argument("--port", type=int, default=8765, help="Bind port")
    return p.parse_args()


if __name__ == "__main__":
    args = _parse_args()
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
