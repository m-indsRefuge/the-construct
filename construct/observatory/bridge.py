"""Async subprocess adapter for the Wolfram-authored world stream."""

from __future__ import annotations

import asyncio
import os
import shutil
import tempfile
from collections.abc import AsyncIterator
from pathlib import Path

from construct.observatory.models import FrameError, WorldFrame, parse_frame

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "scripts" / "observatory_stream.wls"


class StreamError(RuntimeError):
    """The Wolfram process could not start or did not provide valid frames."""


class WolframBridge:
    def __init__(
        self,
        *,
        executable: str | Path | None = None,
        seed: int = 42,
        delay: float = 0.5,
        steps: int = 0,
        max_population: int = 30,
    ) -> None:
        if delay < 0 or steps < 0 or max_population < 1:
            raise ValueError("delay/steps must be non-negative and max_population positive")
        self.executable = str(executable or os.environ.get("WOLFRAMSCRIPT") or "wolframscript")
        self.seed, self.delay, self.steps = seed, delay, steps
        self.max_population = max_population
        self.process: asyncio.subprocess.Process | None = None
        self.stderr_tail: list[str] = []
        self._stderr_task: asyncio.Task[None] | None = None
        self._control_path: Path | None = None

    @staticmethod
    def find_executable() -> str | None:
        configured = os.environ.get("WOLFRAMSCRIPT")
        if configured and Path(configured).is_file():
            return configured
        return shutil.which("wolframscript")

    async def start(self) -> None:
        if self.process is not None:
            return
        if not RUNNER.is_file():
            raise StreamError(f"runner not found: {RUNNER}")
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="ascii",
            suffix=".delay",
            prefix="construct-observatory-",
            delete=False,
        ) as handle:
            self._control_path = Path(handle.name)
            handle.write(str(self.delay))
        try:
            self.process = await asyncio.create_subprocess_exec(
                self.executable,
                "-file",
                str(RUNNER),
                f"--seed={self.seed}",
                f"--delay={self.delay}",
                f"--steps={self.steps}",
                f"--max-population={self.max_population}",
                f"--control-file={self._control_path}",
                cwd=ROOT,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        except (FileNotFoundError, OSError) as exc:
            self._remove_control_file()
            raise StreamError(f"could not launch {self.executable}: {exc}") from exc
        self._stderr_task = asyncio.create_task(self._drain_stderr(self.process))

    def set_delay(self, delay: float) -> None:
        if delay < 0:
            raise ValueError("delay must be non-negative")
        self.delay = delay
        if self._control_path:
            temporary = self._control_path.with_suffix(".next")
            temporary.write_text(str(delay), encoding="ascii")
            temporary.replace(self._control_path)

    def _remove_control_file(self) -> None:
        if self._control_path:
            self._control_path.unlink(missing_ok=True)
            self._control_path.with_suffix(".next").unlink(missing_ok=True)
            self._control_path = None

    async def _drain_stderr(self, process: asyncio.subprocess.Process) -> None:
        assert process.stderr
        while line := await process.stderr.readline():
            self.stderr_tail.append(line.decode("utf-8", errors="replace").rstrip())
            del self.stderr_tail[:-40]

    async def frames(self) -> AsyncIterator[WorldFrame]:
        await self.start()
        process = self.process
        assert process and process.stdout
        while line := await process.stdout.readline():
            try:
                yield parse_frame(line)
            except FrameError as exc:
                raise StreamError(f"invalid Wolfram frame: {exc}") from exc
        code = await process.wait()
        if code:
            diagnostic = "\n".join(self.stderr_tail[-8:]) or "no Wolfram diagnostics"
            raise StreamError(f"wolframscript exited with code {code}:\n{diagnostic}")

    async def terminate(self) -> None:
        process = self.process
        if process and process.returncode is None:
            process.terminate()
            try:
                await asyncio.wait_for(process.wait(), timeout=3)
            except TimeoutError:
                process.kill()
                await process.wait()
        if self._stderr_task:
            await self._stderr_task
            self._stderr_task = None
        self.process = None
        self._remove_control_file()
