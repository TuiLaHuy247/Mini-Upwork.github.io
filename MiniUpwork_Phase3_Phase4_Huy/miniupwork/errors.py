"""Public errors contain safe messages rather than database diagnostics."""


class ServiceError(Exception):
    def __init__(self, message: str, status_code: int, code: str) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.code = code


def not_found(resource: str) -> ServiceError:
    return ServiceError(f"{resource} was not found.", 404, "not_found")


def conflict(message: str, code: str = "state_conflict") -> ServiceError:
    return ServiceError(message, 409, code)


def invalid(message: str, code: str = "invalid_input") -> ServiceError:
    return ServiceError(message, 422, code)
