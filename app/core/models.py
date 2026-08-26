from enum import Enum
from pydantic import BaseModel, Field

class Side(str, Enum):
    BUY = "buy"
    SELL = "sell"

class OrderType(str, Enum):
    MARKET = "market"
    LIMIT = "limit"

class OrderIntent(BaseModel):
    symbol: str = Field(min_length=1, max_length=30)
    side: Side
    quantity: float = Field(gt=0)
    order_type: OrderType = OrderType.MARKET
    limit_price: float | None = Field(default=None, gt=0)

class VirtualPosition(BaseModel):
    symbol: str
    quantity: float = 0
    average_price: float = 0

class DemoPortfolio(BaseModel):
    initial_capital: float = Field(default=10000, gt=0)
    cash: float = Field(default=10000, ge=0)
    realized_pnl: float = 0
    positions: list[VirtualPosition] = []
