"""Validated input contracts for both the CLI and the HTTP interface."""

from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

PositiveId = Annotated[int, Field(gt=0, strict=True)]
Money = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=2)]


class InputModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class JobSkillInput(InputModel):
    skill_id: PositiveId
    required_level: int = Field(ge=1, le=5, strict=True)


class JobBase(InputModel):
    client_id: PositiveId
    category_id: PositiveId
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1, max_length=10000)
    skills: list[JobSkillInput] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def distinct_skills(self):
        ids = [item.skill_id for item in self.skills]
        if len(ids) != len(set(ids)):
            raise ValueError("Each skill_id may appear only once.")
        return self


class FixedPriceJobCreate(JobBase):
    job_type: Literal["FIXED_PRICE"]
    budget_amount: Money


class HourlyJobCreate(JobBase):
    job_type: Literal["HOURLY"]
    rate_min: Money
    rate_max: Money

    @model_validator(mode="after")
    def ordered_rates(self):
        if self.rate_max < self.rate_min:
            raise ValueError("rate_max must be greater than or equal to rate_min.")
        return self


JobCreate = Annotated[
    FixedPriceJobCreate | HourlyJobCreate, Field(discriminator="job_type")
]


class ClientIdentity(InputModel):
    client_id: PositiveId


class FreelancerIdentity(InputModel):
    freelancer_id: PositiveId


class ProposalInput(FreelancerIdentity):
    cover_letter: str = Field(min_length=1, max_length=10000)
    offered_amount: Money

