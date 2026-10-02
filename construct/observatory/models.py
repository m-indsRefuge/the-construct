from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any


class FrameError(ValueError):
    """A JSONL record is not a valid world frame."""


def _integer(data: dict[str, Any], key: str, minimum: int = 0) -> int:
    value = data.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise FrameError(f"{key} must be an integer >= {minimum}")
    return value


@dataclass(frozen=True, slots=True)
class Inhabitant:
    id: str
    generation: int
    parents: tuple[str, ...]
    genome: str
    executions: int
    last_output: Any = None


@dataclass(frozen=True, slots=True)
class Contract:
    id: str
    attempts: int
    passes: int
    reward: int

    @property
    def pass_rate(self) -> float:
        return self.passes / self.attempts if self.attempts else 0.0


@dataclass(frozen=True, slots=True)
class Event:
    id: int
    tick: int
    type: str
    actor: str
    data: dict[str, Any]


@dataclass(frozen=True, slots=True)
class WorldFrame:
    tick: int
    status: str
    compute: int
    memory: int
    population_count: int
    object_count: int
    inhabitants: tuple[Inhabitant, ...]
    contracts: tuple[Contract, ...]
    events: tuple[Event, ...]


def parse_frame(line: str | bytes) -> WorldFrame:
    """Parse one JSONL record and validate all fields used by the UI."""
    try:
        raw = json.loads(line)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise FrameError(f"invalid JSON frame: {exc}") from exc
    if not isinstance(raw, dict):
        raise FrameError("frame must be an object")
    if not isinstance(raw.get("status"), str) or not raw["status"]:
        raise FrameError("status must be a non-empty string")
    population, contracts, events = (raw.get(k) for k in ("population", "contracts", "events"))
    if (
        not isinstance(population, list)
        or not isinstance(contracts, list)
        or not isinstance(events, list)
    ):
        raise FrameError("population, contracts, and events must be arrays")
    inhabitants = []
    for item in population:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise FrameError("each inhabitant needs a string id")
        parents = item.get("parents", [])
        genome = item.get("genome", "")
        if not isinstance(parents, list) or not all(isinstance(p, str) for p in parents):
            raise FrameError(f"invalid parents for {item['id']}")
        if not isinstance(genome, str):
            raise FrameError(f"invalid genome for {item['id']}")
        inhabitants.append(
            Inhabitant(
                item["id"],
                _integer(item, "generation"),
                tuple(parents),
                genome,
                _integer(item, "executions"),
                item.get("last_output"),
            )
        )
    normalized_contracts = []
    for item in contracts:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise FrameError("each contract needs a string id")
        attempts, passes = _integer(item, "attempts"), _integer(item, "passes")
        if passes > attempts:
            raise FrameError(f"passes exceed attempts for {item['id']}")
        normalized_contracts.append(
            Contract(item["id"], attempts, passes, _integer(item, "reward"))
        )
    normalized_events = []
    for item in events:
        if not isinstance(item, dict) or not isinstance(item.get("type"), str):
            raise FrameError("each event needs a type")
        actor, data = item.get("actor"), item.get("data", {})
        if not isinstance(actor, str) or not isinstance(data, dict):
            raise FrameError("invalid event actor or data")
        normalized_events.append(
            Event(_integer(item, "id", 1), _integer(item, "tick"), item["type"], actor, data)
        )
    count = _integer(raw, "population_count")
    if count != len(inhabitants):
        raise FrameError("population_count does not match summaries")
    return WorldFrame(
        _integer(raw, "tick"),
        raw["status"],
        _integer(raw, "compute"),
        _integer(raw, "memory"),
        count,
        _integer(raw, "object_count"),
        tuple(inhabitants),
        tuple(normalized_contracts),
        tuple(normalized_events),
    )
