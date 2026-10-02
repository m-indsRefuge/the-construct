param(
    [string]$WolframScript = "C:\Program Files\Wolfram Research\Wolfram Engine\15.0\wolframscript.exe",
    [double]$Delay = 0.5,
    [int]$Steps = 0
)
$ErrorActionPreference = "Stop"
$env:WOLFRAMSCRIPT = $WolframScript
uv run python -m construct.observatory.app --delay $Delay --steps $Steps

