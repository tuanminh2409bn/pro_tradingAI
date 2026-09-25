"""Closed-schema operational metrics that cannot carry user payloads or secrets."""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Callable


class Operation(str, Enum):
    ANALYSIS = "analysis"
    AI_CHAT = "ai_chat"
    PAPER_EXECUTION = "paper_execution"


class OperationOutcome(str, Enum):
    SUCCESS = "success"
    FAILURE = "failure"
    FALLBACK = "fallback"
    BLOCKED = "blocked"


class FailureCode(str, Enum):
    CONFIG_UNAVAILABLE = "config_unavailable"
    PROVIDER_UNAVAILABLE = "provider_unavailable"
    STORE_UNAVAILABLE = "store_unavailable"
    VALIDATION_FAILED = "validation_failed"
    KILL_SWITCH = "kill_switch"
    INTERNAL_ERROR = "internal_error"


@dataclass(frozen=True)
class OperationMetric:
    operation: Operation
    outcome: OperationOutcome
    latency_ms: int
    fallback: bool
    error_code: FailureCode | None


class OperationRecorder:
    def __init__(
        self,
        *,
        sink: Callable[[OperationMetric], None],
        clock: Callable[[], float] = time.monotonic,
    ):
        self._sink = sink
        self._clock = clock

    def start(self, operation: Operation) -> "OperationTimer":
        if not isinstance(operation, Operation):
            raise ValueError("Unknown measured operation")
        return OperationTimer(
            operation=operation,
            sink=self._sink,
            clock=self._clock,
            started_at=self._clock(),
        )


class OperationTimer:
    def __init__(
        self,
        *,
        operation: Operation,
        sink: Callable[[OperationMetric], None],
        clock: Callable[[], float],
        started_at: float,
    ):
        self._operation = operation
        self._sink = sink
        self._clock = clock
        self._started_at = started_at
        self._finished = False
        self._lock = threading.Lock()

    def finish(
        self,
        *,
        outcome: OperationOutcome,
        fallback: bool,
        error_code: FailureCode | None = None,
    ) -> OperationMetric:
        with self._lock:
            if self._finished:
                raise RuntimeError("Operation metric already finished")
            if not isinstance(outcome, OperationOutcome) or not isinstance(
                fallback, bool
            ):
                raise ValueError("Operation outcome is invalid")
            if outcome in {OperationOutcome.FAILURE, OperationOutcome.BLOCKED}:
                if not isinstance(error_code, FailureCode) or fallback:
                    raise ValueError("Failure metric is invalid")
            elif outcome == OperationOutcome.SUCCESS:
                if error_code is not None or fallback:
                    raise ValueError("Success metric is invalid")
            elif outcome == OperationOutcome.FALLBACK:
                if not fallback:
                    raise ValueError("Fallback metric is invalid")
                if error_code is not None and not isinstance(error_code, FailureCode):
                    raise ValueError("Fallback metric is invalid")

            elapsed = self._clock() - self._started_at
            if elapsed < 0:
                raise ValueError("Operation metric clock moved backwards")
            metric = OperationMetric(
                operation=self._operation,
                outcome=outcome,
                latency_ms=int(round(elapsed * 1000)),
                fallback=fallback,
                error_code=error_code,
            )
            self._sink(metric)
            self._finished = True
            return metric
