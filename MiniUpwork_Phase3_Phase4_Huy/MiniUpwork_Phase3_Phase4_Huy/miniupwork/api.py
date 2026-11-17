"""HTTP facade over the same service used by the CLI."""

from typing import Annotated, Literal

from fastapi import Depends, FastAPI, Path, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from .db import Database
from .errors import ServiceError
from .models import ClientIdentity, FreelancerIdentity, JobCreate, ProposalInput
from .service import MiniUpworkService


def get_service(request: Request) -> MiniUpworkService:
    database = request.app.state.database
    if database is None:
        database = Database.from_env()
    return MiniUpworkService(database)


ServiceDependency = Annotated[MiniUpworkService, Depends(get_service)]
ResourceId = Annotated[int, Path(gt=0)]


def create_app(database_url: str | None = None, *, database: Database | None = None) -> FastAPI:
    """Create an isolated API; tests may inject a DSN without changing the environment.

    Configuration and connections are lazy. An explicitly injected database URL
    is not combined with a password from an unrelated .env file.
    """
    if database_url is not None and database is not None:
        raise ValueError("Pass either database_url or database, not both.")
    application = FastAPI(
        title="Mini-Upwork Lab 2 - local demo",
        version="0.1.0",
        description=(
            "Local learning API for jobs and proposals. client_id and freelancer_id "
            "are supplied demo identities, not authenticated user sessions. "
            "Use only locally; database roles and privileges are a separate layer."
        ),
    )
    application.state.database = database if database is not None else (
        Database(database_url) if database_url is not None else None
    )

    @application.exception_handler(ServiceError)
    async def service_error_handler(request: Request, error: ServiceError):
        return JSONResponse(status_code=error.status_code,
                            content={"detail": {"code": error.code, "message": error.message}})

    @application.exception_handler(RequestValidationError)
    @application.exception_handler(ValidationError)
    async def validation_error_handler(request: Request, error):
        # Keep field locations and explanations; do not reflect input values or
        # a body that might accidentally include local credentials.
        details = [{"loc": list(item["loc"]), "msg": item["msg"], "type": item["type"]}
                   for item in error.errors()]
        return JSONResponse(status_code=422, content={"detail": details})

    @application.get("/health", tags=["Setup"])
    def health(service: ServiceDependency):
        """Check that the configured PostgreSQL connection can execute a query."""
        return service.health()

    @application.get("/reference-data", tags=["Setup"])
    def reference_data(service: ServiceDependency):
        """Discover safe demo identities, categories and skills; never password hashes."""
        return service.reference_data()

    @application.get("/jobs", tags=["Jobs"])
    def list_jobs(
        service: ServiceDependency,
        q: Annotated[str | None, Query(max_length=200)] = None,
        category_id: Annotated[int | None, Query(gt=0)] = None,
        skill_id: Annotated[int | None, Query(gt=0)] = None,
        job_type: Literal["FIXED_PRICE", "HOURLY"] | None = None,
        limit: Annotated[int, Query(ge=1, le=100)] = 20,
        offset: Annotated[int, Query(ge=0)] = 0,
    ):
        """Search only OPEN jobs, ordered by posted_at and job_id descending."""
        return service.list_jobs(q=q, category_id=category_id, skill_id=skill_id,
                                 job_type=job_type, limit=limit, offset=offset)

    @application.get("/jobs/{job_id}", tags=["Jobs"])
    def get_job(job_id: ResourceId, service: ServiceDependency):
        """Read one job with its required skills and the matching price subtype."""
        return service.get_job(job_id)

    @application.post("/jobs", status_code=201, tags=["Jobs"])
    def create_job(body: JobCreate, service: ServiceDependency):
        """Atomically create a DRAFT, exactly one price subtype, and its skill rows."""
        return service.create_job(body)

    @application.post("/jobs/{job_id}/open", tags=["Jobs"])
    def open_job(job_id: ResourceId, body: ClientIdentity, service: ServiceDependency):
        """Open a DRAFT using its supplied demo owner ID; at least one skill is required."""
        return service.open_job(job_id, body.client_id)

    @application.get("/jobs/{job_id}/proposals", tags=["Proposals"])
    def list_proposals(job_id: ResourceId, service: ServiceDependency):
        """List proposals for a job in this local demonstration environment."""
        return service.list_proposals(job_id)

    @application.post("/jobs/{job_id}/proposals", status_code=201, tags=["Proposals"])
    def submit_proposal(job_id: ResourceId, body: ProposalInput, service: ServiceDependency):
        """Submit once per freelancer/job pair; the job must be OPEN and owned by someone else."""
        return service.submit_proposal(job_id, body)

    @application.post("/proposals/{proposal_id}/withdraw", tags=["Proposals"])
    def withdraw_proposal(proposal_id: ResourceId, body: FreelancerIdentity, service: ServiceDependency):
        """Change SUBMITTED to WITHDRAWN without deleting its history."""
        return service.withdraw_proposal(proposal_id, body.freelancer_id)

    @application.post("/proposals/{proposal_id}/resubmit", tags=["Proposals"])
    def resubmit_proposal(proposal_id: ResourceId, body: ProposalInput, service: ServiceDependency):
        """Reuse a WITHDRAWN row with updated content; check the OPEN job again."""
        return service.resubmit_proposal(proposal_id, body)

    return application


# Creating this object neither resolves DATABASE_URL nor opens a DB connection.
app = create_app()
