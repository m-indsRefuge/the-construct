from __future__ import annotations

import argparse
from collections.abc import Iterable
from typing import ClassVar

from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import DataTable, Footer, Header, RichLog, Static

from construct.observatory.bridge import StreamError, WolframBridge
from construct.observatory.models import Event, Inhabitant, WorldFrame

EVENT_COLORS = {
    "CONTRACT_PASSED": "#79f2c0",
    "CONTRACT_FAILED": "#ff7189",
    "INHABITANT_CREATED": "#65d9ff",
    "GENOME_MUTATED": "#d6a3ff",
    "INHABITANTS_COMPOSED": "#f3c969",
    "RESOURCE_SPENT": "#ffb86b",
    "RESOURCE_GRANTED": "#79f2c0",
    "ECOLOGY_ERROR": "#ff526f",
}


def topology_lines(inhabitants: Iterable[Inhabitant], selected: str | None = None) -> list[Text]:
    """Render a deterministic, compact generation/parent topology."""
    ordered = sorted(inhabitants, key=lambda item: (item.generation, item.id))
    known = {item.id for item in ordered}
    children = {item.id: [] for item in ordered}
    for item in ordered:
        for parent in item.parents:
            if parent in known:
                children[parent].append(item.id)
    lines: list[Text] = []
    for item in ordered:
        parent_label = "+".join(item.parents) if item.parents else "ORIGIN"
        connector = "+" if len(item.parents) > 1 else "-"
        label = f"G{item.generation:02}  {connector} {item.id:<6}  <- {parent_label}"
        if children[item.id]:
            label += f"   -> {', '.join(sorted(children[item.id]))}"
        style = (
            "bold #ffffff on #174455"
            if item.id == selected
            else ("#65d9ff" if item.generation == 0 else "#79f2c0")
        )
        lines.append(Text(label, style=style))
    if not lines:
        lines.append(Text("Awaiting first inhabitants.", style="dim"))
    return lines[-18:]


def topology_text(inhabitants: Iterable[Inhabitant], selected: str | None = None) -> Text:
    result = Text()
    for index, line in enumerate(topology_lines(inhabitants, selected)):
        if index:
            result.append("\n")
        result.append(line)
    return result


def format_event(event: Event) -> Text:
    color = EVENT_COLORS.get(event.type, "#8294a8")
    return Text.assemble(
        (f"{event.tick:04} ", "#66798e"),
        (f"{event.type:<21} ", f"bold {color}"),
        (event.actor, "#d7e5ef"),
    )


def unseen_events(events: Iterable[Event], seen: set[int]) -> list[Event]:
    """Return events that have not yet been logged."""
    return [event for event in events if event.id not in seen]


class ObservatoryApp(App[None]):
    TITLE = "THE CONSTRUCT // OBSERVATORY"
    CSS = """
    Screen { background: #080d13; color: #d7e5ef; }
    Header { background: #0d1721; color: #65d9ff; height: 1; }
    Footer { background: #0d1721; color: #8da4b8; }
    #masthead { height: 3; padding: 0 2; background: #101d28; border-bottom: solid #234052; }
    #brand { width: 32; content-align: left middle; color: #65d9ff; text-style: bold; }
    #readout { width: 1fr; content-align: right middle; color: #b7cad8; }
    #body { height: 1fr; padding: 1 1; }
    #left { width: 1.25fr; min-width: 34; }
    #right { width: 1fr; min-width: 38; margin-left: 1; }
    .panel { border: round #234052; background: #0c141c; padding: 0 1; margin-bottom: 1; }
    .panel-title { height: 1; color: #65d9ff; text-style: bold; }
    #topology { height: 1fr; min-height: 10; }
    #contracts { height: 10; }
    #telemetry { height: 6; }
    #inhabitants { height: 1fr; min-height: 9; }
    #details { height: 9; }
    #events { height: 1fr; min-height: 8; padding: 0 1; }
    DataTable { height: 1fr; background: #0c141c; }
    DataTable > .datatable--header { background: #142331; color: #79f2c0; }
    DataTable > .datatable--cursor { background: #174455; color: #ffffff; }
    RichLog { background: #0c141c; scrollbar-color: #234052; }
    """
    BINDINGS: ClassVar[list[tuple[str, str, str]]] = [
        ("q", "quit", "Quit"),
        ("space", "toggle_pause", "Pause view"),
        ("r", "restart", "Restart world"),
        ("up", "select_previous", "Previous"),
        ("down", "select_next", "Next"),
        ("+", "faster", "Faster"),
        ("=", "faster", "Faster"),
        ("-", "slower", "Slower"),
    ]

    def __init__(
        self,
        *,
        seed: int = 42,
        delay: float = 0.5,
        steps: int = 0,
        max_population: int = 30,
        wolframscript: str | None = None,
    ) -> None:
        super().__init__()
        self.seed, self.delay, self.steps = seed, delay, steps
        self.max_population, self.wolframscript = max_population, wolframscript
        self.bridge: WolframBridge | None = None
        self.frame: WorldFrame | None = None
        self.selected_id: str | None = None
        self.paused = False
        self._events_seen: set[int] = set()
        self._restart_requested = False

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="masthead"):
            yield Static("[+] THE CONSTRUCT", id="brand")
            yield Static("WORLD ZERO   |   INITIALIZING", id="readout")
        with Horizontal(id="body"):
            with Vertical(id="left"):
                with Vertical(classes="panel", id="topology"):
                    yield Static("LINEAGE / POPULATION TOPOLOGY", classes="panel-title")
                    yield Static("Awaiting Wolfram frames...", id="topology-view")
                with Vertical(classes="panel", id="contracts"):
                    yield Static("ENVIRONMENT CONTRACTS", classes="panel-title")
                    yield Static("Awaiting contract telemetry...", id="contract-view")
                with Vertical(classes="panel", id="telemetry"):
                    yield Static("RESOURCE TELEMETRY", classes="panel-title")
                    yield Static(
                        "COMPUTE   [--------------------]\nMEMORY    [--------------------]",
                        id="resource-view",
                    )
            with Vertical(id="right"):
                with Vertical(classes="panel", id="inhabitants"):
                    yield Static(
                        "INHABITANT REGISTRY  /  UP DOWN SELECT", classes="panel-title"
                    )
                    yield DataTable(id="inhabitant-table", cursor_type="row", zebra_stripes=True)
                with Vertical(classes="panel", id="details"):
                    yield Static("SELECTED INHABITANT", classes="panel-title")
                    yield Static(
                        "Select a population record to inspect its genome and lineage.",
                        id="detail-view",
                    )
                with Vertical(classes="panel", id="events"):
                    yield Static("EVENT STREAM   /   RECENT", classes="panel-title")
                    yield RichLog(id="event-log", wrap=True, markup=False, highlight=False)
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#inhabitant-table", DataTable).add_columns(
            "ID", "GEN", "PROGRAM", "RUNS", "OUTPUT"
        )
        self._launch_stream()

    @work(exclusive=True, group="stream")
    async def _launch_stream(self) -> None:
        while True:
            self._restart_requested = False
            bridge = WolframBridge(
                executable=self.wolframscript,
                seed=self.seed,
                delay=self.delay,
                steps=self.steps,
                max_population=self.max_population,
            )
            self.bridge = bridge
            restart = False
            try:
                async for frame in bridge.frames():
                    if self._restart_requested:
                        restart = True
                        break
                    if not self.paused:
                        self.apply_frame(frame)
                if self._restart_requested:
                    restart = True
                else:
                    self.set_run_state("COMPLETE", "#f3c969")
                    return
            except StreamError as exc:
                if self._restart_requested:
                    restart = True
                else:
                    self.set_run_state(f"STREAM ERROR: {exc}", "#ff7189")
                    return
            finally:
                await bridge.terminate()
                if self.bridge is bridge:
                    self.bridge = None
            if not restart:
                return
            self._reset_observation()

    def _reset_observation(self) -> None:
        self.frame = None
        self.selected_id = None
        self._events_seen.clear()
        if self.is_mounted:
            self.query_one("#event-log", RichLog).clear()
            self.query_one("#inhabitant-table", DataTable).clear()
            self.query_one("#detail-view", Static).update(
                "Select a population record to inspect its genome and lineage."
            )

    def set_run_state(self, state: str, color: str = "#79f2c0") -> None:
        if self.is_mounted:
            self.query_one("#readout", Static).update(Text(state, style=f"bold {color}"))

    def apply_frame(self, frame: WorldFrame) -> None:
        self.frame = frame
        self.query_one("#readout", Static).update(
            f"TICK {frame.tick:05}   |   POP {frame.population_count:02}   |   "
            f"COMPUTE {frame.compute:04}   |   MEMORY {frame.memory:03}   |   "
            f"{('VIEW PAUSED' if self.paused else frame.status.upper())}"
        )
        self.query_one("#topology-view", Static).update(
            topology_text(frame.inhabitants, self.selected_id)
        )
        table = self.query_one("#inhabitant-table", DataTable)
        previous = self.selected_id
        table.clear()
        for inhabitant in frame.inhabitants:
            output = "-" if inhabitant.last_output is None else str(inhabitant.last_output)
            table.add_row(
                inhabitant.id,
                str(inhabitant.generation),
                inhabitant.genome,
                str(inhabitant.executions),
                output,
                key=inhabitant.id,
            )
        if frame.inhabitants:
            ids = {item.id for item in frame.inhabitants}
            self.selected_id = previous if previous in ids else frame.inhabitants[0].id
            try:
                row = next(
                    i for i, item in enumerate(frame.inhabitants) if item.id == self.selected_id
                )
                table.move_cursor(row=row, animate=False)
            except (IndexError, ValueError):
                pass
        self.update_details()
        contract_rows = [
            f"{item.id:<6} {item.passes:>3}/{item.attempts:<3}  {item.pass_rate:>5.0%}  "
            f"+{item.reward:>2} compute  {'#' * round(item.pass_rate * 12)}"
            f"{'.' * (12 - round(item.pass_rate * 12))}"
            for item in frame.contracts
        ]
        self.query_one("#contract-view", Static).update(
            "\n".join(contract_rows[:5]) or "No contracts"
        )
        compute_fill = min(20, max(0, round(frame.compute / 1000 * 20)))
        memory_fill = min(20, max(0, round(frame.memory / 256 * 20)))
        self.query_one("#resource-view", Static).update(
            f"COMPUTE  {frame.compute:>5}  [{'#' * compute_fill}{'.' * (20 - compute_fill)}]\n"
            f"MEMORY   {frame.memory:>5}  [{'#' * memory_fill}{'.' * (20 - memory_fill)}]"
        )
        log = self.query_one("#event-log", RichLog)
        for event in unseen_events(frame.events, self._events_seen):
            log.write(format_event(event))
            self._events_seen.add(event.id)

    def update_details(self) -> None:
        selected = (
            next((item for item in self.frame.inhabitants if item.id == self.selected_id), None)
            if self.frame
            else None
        )
        if not selected:
            self.query_one("#detail-view", Static).update("No inhabitant selected.")
            return
        parents = " + ".join(selected.parents) if selected.parents else "ORIGIN SEED"
        output = "NOT EXECUTED" if selected.last_output is None else str(selected.last_output)
        self.query_one("#detail-view", Static).update(
            f"{selected.id}   /   GENERATION {selected.generation:02}\n"
            f"LINEAGE   {parents}\nGENOME    {selected.genome}\n"
            f"EXECUTED  {selected.executions} times\nLAST OUT  {output}"
        )

    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        if event.row_key:
            self.selected_id = str(event.row_key.value)
            self.update_details()
            if self.frame:
                self.query_one("#topology-view", Static).update(
                    topology_text(self.frame.inhabitants, self.selected_id)
                )

    def action_toggle_pause(self) -> None:
        self.paused = not self.paused
        self.set_run_state(
            "OBSERVATION PAUSED | WORLD CONTINUES" if self.paused else "OBSERVATION RESUMED",
            "#f3c969" if self.paused else "#79f2c0",
        )

    def action_restart(self) -> None:
        if self.bridge is None:
            self._launch_stream()
            return
        self._restart_requested = True
        self.set_run_state("RESTARTING WORLD", "#f3c969")

    def action_select_previous(self) -> None:
        self.query_one("#inhabitant-table", DataTable).action_cursor_up()

    def action_select_next(self) -> None:
        self.query_one("#inhabitant-table", DataTable).action_cursor_down()

    def _change_delay(self, delay: float) -> None:
        self.delay = min(30.0, max(0.05, delay))
        if self.bridge:
            self.bridge.set_delay(self.delay)
        self.set_run_state(f"ECOLOGY INTERVAL {self.delay:.2f}s", "#f3c969")

    def action_faster(self) -> None:
        self._change_delay(self.delay / 1.5)

    def action_slower(self) -> None:
        self._change_delay(self.delay * 1.5)

    async def on_unmount(self) -> None:
        if self.bridge:
            await self.bridge.terminate()


def main() -> None:
    parser = argparse.ArgumentParser(description="Observe a Wolfram World Zero simulation")
    parser.add_argument("--wolframscript", help="path to wolframscript (or set WOLFRAMSCRIPT)")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--delay", type=float, default=0.5, help="seconds between Wolfram ecology steps"
    )
    parser.add_argument(
        "--steps", type=int, default=0, help="number of steps; 0 streams continuously"
    )
    parser.add_argument("--max-population", type=int, default=30)
    args = parser.parse_args()
    if args.delay < 0 or args.steps < 0 or args.max_population < 1:
        parser.error("delay/steps must be non-negative and max-population positive")
    ObservatoryApp(
        seed=args.seed,
        delay=args.delay,
        steps=args.steps,
        max_population=args.max_population,
        wolframscript=args.wolframscript,
    ).run()


if __name__ == "__main__":
    main()


