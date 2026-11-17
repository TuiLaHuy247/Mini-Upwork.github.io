"""Serve the Phase 4 & Phase 3 screens alongside the Lab 2 API."""

from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .api import create_app
from .db import Database

WEB = Path(__file__).resolve().parent / "web"


def create_phase4_app(database: Database | None = None) -> FastAPI:
    application = create_app(database=database)
    application.title = "Mini-Upwork · Phase 3 & Phase 4 (Đạt & Huy)"
    application.mount("/ui", StaticFiles(directory=WEB), name="phase4-ui")

    @application.get("/", include_in_schema=False)
    def marketplace():
        return FileResponse(WEB / "index.html", headers={"Cache-Control": "no-cache"})

    @application.get("/contracts", include_in_schema=False)
    def contracts_screen():
        return FileResponse(WEB / "contracts.html", headers={"Cache-Control": "no-cache"})

    return application


app = create_phase4_app()
