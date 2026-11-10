"""Password reset for the tenant API."""


def request_reset(email):
    """Start a password reset for an account."""
    return {"email": email, "started": True}
