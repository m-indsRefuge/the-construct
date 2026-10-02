from __future__ import annotations

import json

import pytest

from construct.observatory.app import topology_lines
from construct.observatory.models import FrameError, parse_frame


@pytest.fixture
def raw_frame() -> dict:
    return {
        "tick": 4,
        "status": "running",
        "compute": 900,
        "memory": 250,
        "population_count": 2,
        "object_count": 1,
        "population": [
            {
                "id": "C001",
                "generation": 0,
                "parents": [],
                "genome": "TCProgram[Increment]",
                "executions": 2,
                "last_output": 3,
            },
            {
                "id": "C002",
                "generation": 1,
                "parents": ["C001"],
                "genome": "TCProgram[Double]",
                "executions": 0,
                "last_output": None,
            },
        ],
        "contracts": [{"id": "K001", "attempts": 2, "passes": 1, "reward": 12}],
        "events": [
            {
                "id": 8,
                "tick": 4,
                "type": "CONTRACT_PASSED",
                "actor": "C001",
                "data": {"Contract": "K001"},
            }
        ],
    }


def test_parse_frame_normalizes_summaries(raw_frame: dict) -> None:
    frame = parse_frame(json.dumps(raw_frame))
    assert frame.tick == 4
    assert frame.inhabitants[1].parents == ("C001",)
    assert frame.inhabitants[1].last_output is None
    assert frame.contracts[0].pass_rate == 0.5
    assert frame.events[0].data["Contract"] == "K001"


@pytest.mark.parametrize(
    "edit",
    [
        lambda frame: frame.update(tick=True),
        lambda frame: frame.update(population_count=99),
        lambda frame: frame.update(
            contracts=[{"id": "K", "attempts": 1, "passes": 2, "reward": 3}]
        ),
        lambda frame: frame.update(
            population=[
                {"id": "C", "generation": -1, "parents": [], "genome": "x", "executions": 0}
            ]
        ),
    ],
)
def test_parse_frame_rejects_invalid_data(raw_frame: dict, edit) -> None:
    edit(raw_frame)
    with pytest.raises(FrameError):
        parse_frame(json.dumps(raw_frame))


def test_parse_frame_rejects_non_json() -> None:
    with pytest.raises(FrameError, match="invalid JSON"):
        parse_frame("kernel chatter")


def test_topology_shows_mutation_and_composite_lineage() -> None:
    frame = parse_frame(
        json.dumps(
            {
                "tick": 1,
                "status": "running",
                "compute": 10,
                "memory": 20,
                "population_count": 3,
                "object_count": 0,
                "population": [
                    {"id": "C001", "generation": 0, "parents": [], "genome": "A", "executions": 0},
                    {
                        "id": "C002",
                        "generation": 1,
                        "parents": ["C001"],
                        "genome": "B",
                        "executions": 0,
                    },
                    {
                        "id": "C003",
                        "generation": 1,
                        "parents": ["C001", "C002"],
                        "genome": "C",
                        "executions": 0,
                    },
                ],
                "contracts": [],
                "events": [],
            }
        )
    )
    lines = topology_lines(frame.inhabitants, selected="C003")
    assert "C001" in "\n".join(row.plain for row in lines)
    assert "C001+C002" in lines[-1].plain
    assert "+" in lines[-1].plain
    assert "C003" in lines[-1].plain


def test_unseen_events_logs_each_event_once(raw_frame: dict) -> None:
    from construct.observatory.app import unseen_events

    frame = parse_frame(json.dumps(raw_frame))
    seen: set[int] = set()
    assert [event.id for event in unseen_events(frame.events, seen)] == [8]
    assert seen == set()
    seen.add(8)
    assert unseen_events(frame.events, seen) == []





def test_powershell_launcher_uses_module_invocation() -> None:
    from pathlib import Path

    launcher = Path(__file__).parents[1] / "scripts" / "run_observatory.ps1"
    source = launcher.read_text(encoding="utf-8")
    assert "$env:WOLFRAMSCRIPT = $WolframScript" in source
    assert "uv run python -m construct.observatory.app --delay $Delay --steps $Steps" in source

def test_wolfram_exporter_contract_is_fail_fast_and_bounded() -> None:
    from pathlib import Path

    exporter = Path(__file__).parents[1] / "scripts" / "observatory_stream.wls"
    source = exporter.read_text(encoding="ascii")
    assert "Association @ KeyValueMap[#1 -> jsonValue[#2] &, value]" in source
    assert "Rest[$ScriptCommandLine]" in source
    assert "StringPosition[token, \"=\", 1]" in source
    assert "value = arguments[[index]]" in source
    assert "While[steps == 0 || tick < steps," in source
    assert "failed to export a JSON frame." in source
    assert "$Messages = {$StandardErrorStream};" in source
    assert "Exit[1]" in source


