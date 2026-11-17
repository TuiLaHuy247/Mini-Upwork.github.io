"""Read configuration lazily; importing the API never connects to PostgreSQL."""

from dataclasses import dataclass
import os

from dotenv import dotenv_values

from .errors import ServiceError


@dataclass(frozen=True)
class Settings:
    database_url: str
    database_password: str | None = None

    @classmethod
    def from_env(cls) -> "Settings":
        # Existing environment variables win over this working directory's .env.
        values = {**dotenv_values(".env"), **os.environ}
        url = str(values.get("DATABASE_URL") or "").strip()
        if not url:
            raise ServiceError(
                "Database configuration is missing. Set DATABASE_URL in your environment or .env.",
                503,
                "database_not_configured",
            )
        password = values.get("DATABASE_PASSWORD") or None
        return cls(database_url=url, database_password=password)
