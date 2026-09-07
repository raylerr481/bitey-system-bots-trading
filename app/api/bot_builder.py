from fastapi import APIRouter
from app.bot_builder.engine import build_bot
from app.bot_builder.spec import BotSpecification

router = APIRouter(prefix="/api/v1/bot-builder", tags=["bot-builder"])

@router.get("/catalog")
def catalog():
    return {"contract":"sbt-bot-v1","languages":["python","mql5","pine","typescript"],"steps":["specify","quant","backtest","stress-test","risk-gate","virtual-validation","generate"],"live":False,"real_money":False,"broker_orders":0}

@router.post("/build")
def build(spec: BotSpecification):
    return build_bot(spec)
