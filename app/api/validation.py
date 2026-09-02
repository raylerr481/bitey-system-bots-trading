from fastapi import APIRouter

from app.services.virtual_validation import run_virtual_validation

router = APIRouter(prefix="/api/v1/validation", tags=["validation"])


def _run():
    """Run the reproducible, deterministic virtual-only validation fixture."""
    return run_virtual_validation()


@router.get("/virtual")
def virtual_validation_get():
    return _run()


@router.post("/virtual")
def virtual_validation_post():
    return _run()
