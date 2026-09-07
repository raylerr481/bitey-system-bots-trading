from fastapi import APIRouter

from app.bot_builder.video_hypothesis import alex_ruiz_hypothesis

router = APIRouter(prefix="/api/v1/video-hypothesis", tags=["video-hypothesis"])


@router.get("/alex-ruiz")
def alex_ruiz():
    """Return a testable quantitative hypothesis extracted from educational material."""
    return alex_ruiz_hypothesis()
