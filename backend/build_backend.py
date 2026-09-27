"""Bundle the backend into a standalone executable with PyInstaller.

Run with the interpreter whose site-packages should be bundled (the build
venv set up by scripts/build_all.*):

    python build_backend.py            # dist/diagnostic_backend[.exe]
    python build_backend.py --onedir   # dist/diagnostic_backend/ folder
    python build_backend.py --onedir --zip
        # ...plus dist/diagnostic_backend.zip and dist/diagnostic_backend.sha256

--onefile unpacks itself to a temp directory on every launch, which costs a
few seconds with Orange's dependency tree; --onedir skips that at the price
of shipping a folder instead of a single file. The release app ships the
folder zipped (a Flutter asset has to be a single file) and unpacks it once.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent
NAME = "diagnostic_backend"


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Build the diagnostic backend executable")
    p.add_argument(
        "--onedir",
        action="store_true",
        help="Build a folder instead of a single file (faster startup)",
    )
    p.add_argument(
        "--zip",
        action="store_true",
        help="With --onedir: also pack the folder into a zip and write its SHA256",
    )
    args = p.parse_args()
    if args.zip and not args.onedir:
        p.error("--zip needs --onedir")
    return args


def _zip_dir(src: Path, dest: Path) -> str:
    """Zip the contents of [src] (not the folder itself) and return the SHA256."""
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(src.rglob("*")):
            if f.is_file():
                zf.write(f, f.relative_to(src).as_posix())
    h = hashlib.sha256()
    with dest.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    args = _parse_args()

    try:
        import PyInstaller.__main__
    except ImportError:
        print(
            "PyInstaller is not installed in this interpreter "
            f"({sys.executable}).\nRun: python -m pip install pyinstaller",
            file=sys.stderr,
        )
        return 1

    build_dir = BACKEND_DIR / "build"
    # A console program started from the GUI app gets a console window of its
    # own on Windows, and Dart's Process.start has no way to suppress it.
    windows_only = ["--noconsole"] if sys.platform == "win32" else []
    PyInstaller.__main__.run(
        windows_only + [
            str(BACKEND_DIR / "main.py"),
            "--name", NAME,
            "--onedir" if args.onedir else "--onefile",
            "--noconfirm",
            "--clean",
            "--distpath", str(BACKEND_DIR / "dist"),
            "--workpath", str(build_dir),
            "--specpath", str(build_dir),
            # Orange loads learners, preprocessors and their data files by
            # module path when a .pkcls is unpickled, so static analysis of
            # main.py cannot see what a given model needs: take all of it.
            "--collect-all", "Orange",
            # uvicorn picks its protocol, loop and lifespan implementations by
            # import string at runtime.
            "--collect-submodules", "uvicorn",
        ]
    )

    dist = BACKEND_DIR / "dist"
    exe = NAME + (".exe" if sys.platform == "win32" else "")
    out = dist / (Path(NAME) / exe if args.onedir else Path(exe))
    print(f"\nBuilt {out}")

    if args.zip:
        archive = dist / f"{NAME}.zip"
        digest = _zip_dir(dist / NAME, archive)
        # The app checks the zip against this before unpacking it.
        (dist / f"{NAME}.sha256").write_text(digest, encoding="ascii")
        print(f"Packed {archive}  sha256 {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
