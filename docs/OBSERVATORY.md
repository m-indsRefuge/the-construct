# The Construct Observatory

Subsystem 4 adds a live terminal window onto World Zero. Wolfram Language remains the only owner of world state, ecology, inhabitants, contracts, and evolution. The Python/Textual application consumes JSON Lines snapshots and renders them; it does not simulate or mutate the world.

## Launch on Windows

From the repository root, with `uv` installed:

```powershell
.\scripts\run_observatory.ps1
```

The launcher defaults to the Wolfram Engine 15 executable. Override it when needed:

```powershell
.\scripts\run_observatory.ps1 -WolframScript 'C:\path\to\wolframscript.exe' -Delay 0.25 -Steps 500
```

Or launch directly:

```powershell
$env:WOLFRAMSCRIPT = 'C:\Program Files\Wolfram Research\Wolfram Engine\15.0\wolframscript.exe'
uv run python -m construct.observatory.app --delay 0.5 --steps 0
```

`--steps 0` streams continuously. A positive step count exits after that many ecology steps. `--delay` sets the interval between Wolfram ecology steps. The JSONL runner can also be invoked directly with `wolframscript -file scripts/observatory_stream.wls --delay=0.5 --steps=10`; stdout contains only JSON frames and Wolfram diagnostics go to stderr.

## Controls

- `q`: quit and terminate the Wolfram child process
- `Space`: pause/resume displayed observations; Wolfram continues advancing while the view is paused
- `r`: restart a fresh World Zero with the configured seed
- `Up` / `Down`: select an inhabitant and inspect its details
- `+` / `-`: adjust the ecology step interval live through a private control file

No shell execution, external service, OpenClaw integration, or Steward interface is included.

## Observatory view

The main panels show tick/status/resources, an ancestry view that distinguishes composite children, inhabitants and last outputs, contract pass rates/rewards, and a color-coded recent event stream. The Wolfram runner exports compact summaries plus a recent event window. Frame parsing validates schema and counters before display.
