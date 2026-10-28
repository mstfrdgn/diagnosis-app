from __future__ import annotations

import argparse
import faulthandler
import os
import sys
import time
import traceback

# Nothing heavy is imported at module level: FastAPI, uvicorn and above all
# Orange (via the routers) are imported in _run(), after the log file is set
# up, so that a failing import ends up in the log instead of nowhere.


def create_app():
    """Build the FastAPI app. Imports the routers, and with them Orange."""
    from fastapi import FastAPI
    from fastapi.middleware.cors import CORSMiddleware

    from routers import model_router, predict_router

    app = FastAPI(title="Diagnostic App Backend", version="1.1.0")

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

    return app


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Diagnostic App backend")
    p.add_argument("--host", default="127.0.0.1", help="Bind host")
    p.add_argument("--port", type=int, default=8765, help="Bind port")
    p.add_argument(
        "--log-file",
        help="Append all output to this file instead of stdout/stderr",
    )
    return p.parse_args()


def _setup_output(log_file: str | None) -> None:
    if log_file:
        # The Windows bundle is built without a console, and whether it then
        # gets the app's pipes as stdout/stderr is up to the bootloader. A
        # file it opens itself always works.
        try:
            stream = open(log_file, "a", buffering=1, encoding="utf-8", errors="replace")
        except OSError:
            stream = None
        if stream is not None:
            sys.stdout = sys.stderr = stream
            # Native crashes (a broken DLL, say) kill the process without a
            # Python traceback; this at least records where it happened.
            faulthandler.enable(stream)
            return
    # Without a console and without a log file there may be no stdout/stderr
    # at all, and uvicorn logs to them.
    for name in ("stdout", "stderr"):
        if getattr(sys, name) is None:
            setattr(sys, name, open(os.devnull, "w"))


def _log(message: str) -> None:
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} backend: {message}", flush=True)


def _run(args: argparse.Namespace) -> None:
    _log(
        f"starting (pid {os.getpid()}, python {sys.version.split()[0]}, "
        f"exe {sys.executable})"
    )
    t0 = time.monotonic()
    import uvicorn

    app = create_app()
    _log(f"modules loaded in {time.monotonic() - t0:.1f} s")
    _log(f"binding {args.host}:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    args = _parse_args()
    _setup_output(args.log_file)
    try:
        _run(args)
    except SystemExit:
        # uvicorn exits this way (code 3) when it cannot start, e.g. on a
        # bind error, after logging why.
        raise
    except BaseException:
        # Uncaught, a windowed PyInstaller build shows the traceback in a
        # message box and stays alive until someone closes it, which to the
        # app looks like a backend that never answers. Log it and exit.
        _log("crashed during startup:")
        traceback.print_exc()
        sys.stdout.flush()
        # 70 (EX_SOFTWARE): distinct from uvicorn's own startup failure.
        sys.exit(70)
