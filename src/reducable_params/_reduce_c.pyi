from collections.abc import Callable as Callable
from typing import Any, Generic, ParamSpec, TypeVar

T = TypeVar("T")
P = ParamSpec("P")

class reduce(Generic[P, T]):
    __wrapped__: Callable[P, T]
    def __init__(self, func: Callable[P, T]) -> None: ...
    def install(self, *args: P.args, **kwargs: P.kwargs) -> dict[str, Any]: ...
    def __call__(self, /, kwds: dict[str, Any]) -> T: ...
