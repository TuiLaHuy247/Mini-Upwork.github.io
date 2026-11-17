"""Small psycopg 3 connection factory shared by every entry point."""

from contextlib import contextmanager
from dataclasses import dataclass
from typing import Iterator

import psycopg
from psycopg.rows import dict_row

from .config import Settings


@dataclass(frozen=True)
class Database:
    conninfo: str
    password: str | None = None

    @classmethod
    def from_env(cls) -> "Database":
        settings = Settings.from_env()
        return cls(settings.database_url, settings.database_password)

    @contextmanager
    def connection(self) -> Iterator[psycopg.Connection]:
        options = {
            "row_factory": dict_row,
            "connect_timeout": 5,
            "application_name": "miniupwork_lab2",
        }
        if self.password is not None:
            options["password"] = self.password
        # Normal exit commits; errors roll back. Both paths close the connection,
        # including commit errors raised by a deferred database constraint.
        with psycopg.connect(self.conninfo, **options) as connection:
            yield connection
