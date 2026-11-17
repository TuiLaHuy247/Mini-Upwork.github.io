"""Database operations shared by the command line and HTTP API.

Every operation owns one transaction and closes its connection on success or
failure. No input value is interpolated into SQL text.
"""

from datetime import date, datetime
from decimal import Decimal
from functools import wraps
from typing import Any

import psycopg
from pydantic import TypeAdapter

from .db import Database
from .errors import ServiceError, conflict, invalid, not_found
from .models import FixedPriceJobCreate, JobCreate, ProposalInput

_JOB_INPUT = TypeAdapter(JobCreate)
_STATE_CONSTRAINTS = {
    "job_initial_status",
    "job_invalid_transition",
    "job_requires_skill",
    "proposal_requires_open_job",
    "proposal_self_bid",
    "proposal_initial_status",
    "proposal_invalid_transition",
    "proposal_withdraw_changes",
    "immutable_identifier",
}


def json_safe(value: Any) -> Any:
    """Emit JSON numbers for money; PostgreSQL still stores exact NUMERIC values."""
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [json_safe(item) for item in value]
    return value


def database_errors(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        try:
            return function(*args, **kwargs)
        except ServiceError:
            raise
        except psycopg.errors.UniqueViolation:
            raise conflict("This record conflicts with an existing record.", "duplicate_record") from None
        except psycopg.errors.ForeignKeyViolation:
            raise invalid("A referenced record is missing or still in use.", "invalid_reference") from None
        except psycopg.errors.CheckViolation as error:
            if error.diag.constraint_name in _STATE_CONSTRAINTS:
                raise conflict("The operation conflicts with the current business state.") from None
            raise invalid("The data violate a database business rule.", "business_rule_violation") from None
        except (psycopg.errors.NotNullViolation, psycopg.errors.NumericValueOutOfRange,
                psycopg.errors.StringDataRightTruncation, psycopg.errors.InvalidTextRepresentation):
            raise invalid("A value is outside the permitted domain.") from None
        except (psycopg.errors.SerializationFailure, psycopg.errors.DeadlockDetected):
            raise conflict("Another transaction changed this data. Retry the operation.", "concurrent_change") from None
        except psycopg.Error:
            # Never return raw SQL, a server diagnostic, or a connection string.
            raise ServiceError("The database is unavailable or its access configuration needs attention.",
                               503, "database_unavailable") from None
    return wrapped


_JOB_SELECT = """
    SELECT j.job_id, j.client_id, j.category_id, j.title, j.description,
           j.status, j.job_type, j.posted_at, c.category_name,
           u.full_name AS client_name, fp.budget_amount, hp.rate_min, hp.rate_max
    FROM miniupwork.job AS j
    JOIN miniupwork.category AS c ON c.category_id = j.category_id
    JOIN miniupwork.app_user AS u ON u.user_id = j.client_id
    LEFT JOIN miniupwork.fixed_price_job AS fp ON fp.job_id = j.job_id
    LEFT JOIN miniupwork.hourly_job AS hp ON hp.job_id = j.job_id
"""
_PROPOSAL_SELECT = """
    SELECT p.proposal_id, p.job_id, p.freelancer_id, p.cover_letter,
           p.offered_amount, p.status, p.submitted_at,
           u.full_name AS freelancer_name
    FROM miniupwork.proposal AS p
    JOIN miniupwork.app_user AS u ON u.user_id = p.freelancer_id
"""


class MiniUpworkService:
    def __init__(self, database: Database | str) -> None:
        self.database = Database(database) if isinstance(database, str) else database

    @staticmethod
    def _positive_id(value: int) -> None:
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise invalid("IDs must be positive integers.")

    @staticmethod
    def _job(connection, job_id: int, *, lock: bool = False) -> dict:
        query = """SELECT job_id, client_id, category_id, title, description,
                          status, job_type, posted_at
                   FROM miniupwork.job WHERE job_id = %s"""
        if lock:
            query += " FOR UPDATE"
        row = connection.execute(query, (job_id,)).fetchone()
        if row is None:
            raise not_found("Job")
        return row

    @staticmethod
    def _active_profile(connection, profile: str, user_id: int) -> None:
        # Only these two fixed SQL statements are selectable, never a user table name.
        queries = {
            "client": """SELECT u.status FROM miniupwork.client AS p
                         JOIN miniupwork.app_user AS u ON u.user_id = p.user_id
                         WHERE p.user_id = %s""",
            "freelancer": """SELECT u.status FROM miniupwork.freelancer AS p
                             JOIN miniupwork.app_user AS u ON u.user_id = p.user_id
                             WHERE p.user_id = %s""",
        }
        row = connection.execute(queries[profile], (user_id,)).fetchone()
        if row is None:
            raise not_found(profile.capitalize() + " profile")
        if row["status"] != "ACTIVE":
            raise conflict("The supplied demo profile is inactive.", "inactive_profile")

    @staticmethod
    def _pricing(row: dict) -> dict:
        item = dict(row)
        budget = item.pop("budget_amount")
        rate_min = item.pop("rate_min")
        rate_max = item.pop("rate_max")
        if item["job_type"] == "FIXED_PRICE":
            item["pricing"] = {"job_type": "FIXED_PRICE", "budget_amount": budget}
        else:
            item["pricing"] = {"job_type": "HOURLY", "rate_min": rate_min, "rate_max": rate_max}
        return item

    def _job_document(self, connection, job_id: int) -> dict:
        row = connection.execute(_JOB_SELECT + " WHERE j.job_id = %s", (job_id,)).fetchone()
        if row is None:
            raise not_found("Job")
        item = self._pricing(row)
        item["skills"] = connection.execute(
            """SELECT s.skill_id, s.skill_name, js.required_level
               FROM miniupwork.job_skill AS js
               JOIN miniupwork.skill AS s ON s.skill_id = js.skill_id
               WHERE js.job_id = %s ORDER BY s.skill_id""", (job_id,)
        ).fetchall()
        return json_safe(item)

    @staticmethod
    def _proposal_document(connection, proposal_id: int) -> dict:
        row = connection.execute(_PROPOSAL_SELECT + " WHERE p.proposal_id = %s", (proposal_id,)).fetchone()
        if row is None:
            raise not_found("Proposal")
        return json_safe(row)

    @database_errors
    def health(self) -> dict:
        with self.database.connection() as connection:
            connection.execute("SELECT 1 AS ok").fetchone()
        return {"status": "ok", "database": "ok"}

    @database_errors
    def reference_data(self) -> dict:
        with self.database.connection() as connection:
            clients = connection.execute(
                """SELECT c.user_id AS client_id, u.full_name, u.status, c.company_name
                   FROM miniupwork.client AS c
                   JOIN miniupwork.app_user AS u ON u.user_id = c.user_id
                   ORDER BY c.user_id"""
            ).fetchall()
            freelancers = connection.execute(
                """SELECT f.user_id AS freelancer_id, u.full_name, u.status, f.headline,
                          f.default_hourly_rate, f.availability
                   FROM miniupwork.freelancer AS f
                   JOIN miniupwork.app_user AS u ON u.user_id = f.user_id
                   ORDER BY f.user_id"""
            ).fetchall()
            categories = connection.execute(
                """SELECT category_id, parent_category_id, category_name
                   FROM miniupwork.category ORDER BY category_id"""
            ).fetchall()
            skills = connection.execute(
                "SELECT skill_id, skill_name FROM miniupwork.skill ORDER BY skill_id"
            ).fetchall()
        return json_safe({"clients": clients, "freelancers": freelancers,
                          "categories": categories, "skills": skills})

    @database_errors
    def list_jobs(self, *, q: str | None = None, category_id: int | None = None,
                  skill_id: int | None = None, job_type: str | None = None,
                  limit: int = 20, offset: int = 0) -> dict:
        if not 1 <= limit <= 100 or offset < 0:
            raise invalid("limit must be 1..100 and offset must be nonnegative.")
        clauses = ["j.status = 'OPEN'"]
        params = []
        if q is not None:
            q = q.strip()
            if len(q) > 200:
                raise invalid("The search text must be at most 200 characters.")
            if q:
                clauses.append("(j.title ILIKE %s OR j.description ILIKE %s)")
                params.extend([f"%{q}%", f"%{q}%"])
        if category_id is not None:
            self._positive_id(category_id)
            clauses.append("j.category_id = %s")
            params.append(category_id)
        if skill_id is not None:
            self._positive_id(skill_id)
            clauses.append("EXISTS (SELECT 1 FROM miniupwork.job_skill AS js WHERE js.job_id = j.job_id AND js.skill_id = %s)")
            params.append(skill_id)
        if job_type is not None:
            if job_type not in {"FIXED_PRICE", "HOURLY"}:
                raise invalid("job_type must be FIXED_PRICE or HOURLY.")
            clauses.append("j.job_type = %s")
            params.append(job_type)
        where = " WHERE " + " AND ".join(clauses)
        with self.database.connection() as connection:
            total = connection.execute(
                "SELECT COUNT(*) AS total FROM miniupwork.job AS j" + where, params
            ).fetchone()["total"]
            rows = connection.execute(
                _JOB_SELECT + where + " ORDER BY j.posted_at DESC, j.job_id DESC LIMIT %s OFFSET %s",
                [*params, limit, offset],
            ).fetchall()
        return json_safe({"items": [self._pricing(row) for row in rows], "total": total,
                          "limit": limit, "offset": offset})

    @database_errors
    def get_job(self, job_id: int) -> dict:
        self._positive_id(job_id)
        with self.database.connection() as connection:
            return self._job_document(connection, job_id)

    @database_errors
    def create_job(self, data: JobCreate | dict) -> dict:
        data = _JOB_INPUT.validate_python(data)
        with self.database.connection() as connection:
            self._active_profile(connection, "client", data.client_id)
            category = connection.execute(
                "SELECT category_id FROM miniupwork.category WHERE category_id = %s", (data.category_id,)
            ).fetchone()
            if category is None:
                raise not_found("Category")
            if data.skills:
                skill_ids = [skill.skill_id for skill in data.skills]
                found = connection.execute(
                    "SELECT skill_id FROM miniupwork.skill WHERE skill_id = ANY(%s::bigint[])", (skill_ids,)
                ).fetchall()
                if len(found) != len(skill_ids):
                    raise not_found("Skill")
            job_id = connection.execute(
                """INSERT INTO miniupwork.job
                   (client_id, category_id, title, description, status, job_type)
                   VALUES (%s, %s, %s, %s, 'DRAFT', %s) RETURNING job_id""",
                (data.client_id, data.category_id, data.title, data.description, data.job_type),
            ).fetchone()["job_id"]
            if isinstance(data, FixedPriceJobCreate):
                connection.execute(
                    "INSERT INTO miniupwork.fixed_price_job (job_id, budget_amount) VALUES (%s, %s)",
                    (job_id, data.budget_amount),
                )
            else:
                connection.execute(
                    "INSERT INTO miniupwork.hourly_job (job_id, rate_min, rate_max) VALUES (%s, %s, %s)",
                    (job_id, data.rate_min, data.rate_max),
                )
            for skill in data.skills:
                connection.execute(
                    "INSERT INTO miniupwork.job_skill (job_id, skill_id, required_level) VALUES (%s, %s, %s)",
                    (job_id, skill.skill_id, skill.required_level),
                )
            result = self._job_document(connection, job_id)
        return result

    @database_errors
    def open_job(self, job_id: int, client_id: int) -> dict:
        self._positive_id(job_id)
        self._positive_id(client_id)
        with self.database.connection() as connection:
            job = self._job(connection, job_id, lock=True)
            if job["client_id"] != client_id:
                raise conflict("The supplied demo client_id does not own this job.", "owner_mismatch")
            self._active_profile(connection, "client", client_id)
            if job["status"] != "DRAFT":
                raise conflict("Only a DRAFT job can be opened.")
            if connection.execute(
                "SELECT 1 FROM miniupwork.job_skill WHERE job_id = %s LIMIT 1", (job_id,)
            ).fetchone() is None:
                raise conflict("Add at least one required skill before opening the job.", "job_requires_skill")
            connection.execute("UPDATE miniupwork.job SET status = 'OPEN' WHERE job_id = %s", (job_id,))
            result = self._job_document(connection, job_id)
        return result

    @database_errors
    def list_proposals(self, job_id: int) -> list[dict]:
        self._positive_id(job_id)
        with self.database.connection() as connection:
            self._job(connection, job_id)
            rows = connection.execute(
                _PROPOSAL_SELECT + " WHERE p.job_id = %s ORDER BY p.proposal_id", (job_id,)
            ).fetchall()
        return json_safe(rows)

    @database_errors
    def submit_proposal(self, job_id: int, data: ProposalInput | dict) -> dict:
        self._positive_id(job_id)
        data = ProposalInput.model_validate(data)
        with self.database.connection() as connection:
            job = self._job(connection, job_id, lock=True)
            self._active_profile(connection, "freelancer", data.freelancer_id)
            self._can_submit(job, data.freelancer_id)
            proposal_id = connection.execute(
                """INSERT INTO miniupwork.proposal
                   (job_id, freelancer_id, cover_letter, offered_amount, status)
                   VALUES (%s, %s, %s, %s, 'SUBMITTED') RETURNING proposal_id""",
                (job_id, data.freelancer_id, data.cover_letter, data.offered_amount),
            ).fetchone()["proposal_id"]
            result = self._proposal_document(connection, proposal_id)
        return result

    @staticmethod
    def _can_submit(job: dict, freelancer_id: int) -> None:
        if job["status"] != "OPEN":
            raise conflict("Proposals can be submitted only to an OPEN job.")
        if job["client_id"] == freelancer_id:
            raise conflict("A user cannot apply to their own job.", "self_bid")

    def _locked_proposal(self, connection, proposal_id: int) -> tuple[dict, dict]:
        # Acquire parent job first for every transition; the SQL guard uses the
        # same order to serialize submissions with job closure.
        pointer = connection.execute(
            "SELECT job_id FROM miniupwork.proposal WHERE proposal_id = %s", (proposal_id,)
        ).fetchone()
        if pointer is None:
            raise not_found("Proposal")
        job = self._job(connection, pointer["job_id"], lock=True)
        proposal = connection.execute(
            """SELECT proposal_id, job_id, freelancer_id, status
               FROM miniupwork.proposal WHERE proposal_id = %s FOR UPDATE""", (proposal_id,)
        ).fetchone()
        if proposal is None:
            raise not_found("Proposal")
        return job, proposal

    @database_errors
    def withdraw_proposal(self, proposal_id: int, freelancer_id: int) -> dict:
        self._positive_id(proposal_id)
        self._positive_id(freelancer_id)
        with self.database.connection() as connection:
            _, proposal = self._locked_proposal(connection, proposal_id)
            if proposal["freelancer_id"] != freelancer_id:
                raise conflict("The supplied demo freelancer_id does not own this proposal.", "owner_mismatch")
            if proposal["status"] != "SUBMITTED":
                raise conflict("Only a SUBMITTED proposal can be withdrawn.")
            connection.execute(
                "UPDATE miniupwork.proposal SET status = 'WITHDRAWN' WHERE proposal_id = %s", (proposal_id,)
            )
            result = self._proposal_document(connection, proposal_id)
        return result

    @database_errors
    def resubmit_proposal(self, proposal_id: int, data: ProposalInput | dict) -> dict:
        self._positive_id(proposal_id)
        data = ProposalInput.model_validate(data)
        with self.database.connection() as connection:
            job, proposal = self._locked_proposal(connection, proposal_id)
            if proposal["freelancer_id"] != data.freelancer_id:
                raise conflict("The supplied demo freelancer_id does not own this proposal.", "owner_mismatch")
            self._active_profile(connection, "freelancer", data.freelancer_id)
            if proposal["status"] != "WITHDRAWN":
                raise conflict("Only a WITHDRAWN proposal can be resubmitted.")
            self._can_submit(job, data.freelancer_id)
            connection.execute(
                """UPDATE miniupwork.proposal
                   SET cover_letter = %s, offered_amount = %s, status = 'SUBMITTED',
                       submitted_at = CURRENT_TIMESTAMP WHERE proposal_id = %s""",
                (data.cover_letter, data.offered_amount, proposal_id),
            )
            result = self._proposal_document(connection, proposal_id)
        return result


# A short alias is convenient for use in a lesson notebook or small Python script.
Service = MiniUpworkService

