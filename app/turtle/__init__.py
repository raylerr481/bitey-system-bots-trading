"""Classic Turtle Trading controller for Bitey SBT.

The Turtle core is deterministic. Bitey may diagnose implementation problems
and produce bounded correction plans, but it cannot rewrite trading rules
outside the approved baseline contract.
"""
from .controller import TurtleController
from .spec import TURTLE_V122_BASELINE

__all__ = ["TurtleController", "TURTLE_V122_BASELINE"]
