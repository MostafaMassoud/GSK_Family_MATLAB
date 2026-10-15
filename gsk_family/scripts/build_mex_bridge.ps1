# Builds the optional gskcec_eval MEX bridge (MATLAB -> ported C++ CEC
# benchmarks) with a C++20 MinGW-w64 toolchain, without requiring the
# MATLAB 'mex' command or its (older) bundled compiler.
#
# Usage:
#   powershell -File scripts\build_mex_bridge.ps1 `
#       [-MatlabRoot "C:\Program Files\MATLAB\R2025b"] [-Gxx <path-to-g++.exe>]
#
# Defaults: MatlabRoot is derived from 'matlab' on PATH or the GSKCEC_MATLAB
# environment variable; Gxx from g++ on PATH. Output: build\mex\gskcec_eval.mexw64

param(
    [string]$MatlabRoot = "",
    [string]$Gxx = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-MatlabRoot {
    param([string]$Given)
    if ($Given -ne "") { return $Given }
    if ($env:GSKCEC_MATLAB -and (Test-Path $env:GSKCEC_MATLAB)) {
        # GSKCEC_MATLAB points at matlab.exe (<root>\bin\matlab.exe)
        return (Split-Path -Parent (Split-Path -Parent $env:GSKCEC_MATLAB))
    }
    $cmd = Get-Command matlab.exe -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path -Parent (Split-Path -Parent $cmd.Source)) }
    throw "MATLAB not found. Pass -MatlabRoot or set GSKCEC_MATLAB to matlab.exe."
}

function Resolve-Gxx {
    param([string]$Given)
    if ($Given -ne "") { return $Given }
    $cmd = Get-Command g++.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $winget = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $winget) {
        $hit = Get-ChildItem -Path $winget -Recurse -Filter g++.exe -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw "g++ not found. Pass -Gxx with a C++20-capable MinGW-w64 g++."
}

$MatlabRoot = Resolve-MatlabRoot -Given $MatlabRoot
$Gxx = Resolve-Gxx -Given $Gxx

$externInc = Join-Path $MatlabRoot "extern\include"
$externLib = Join-Path $MatlabRoot "extern\lib\win64\mingw64"
if (-not (Test-Path (Join-Path $externInc "mex.h"))) { throw "mex.h not found under $externInc" }
if (-not (Test-Path (Join-Path $externLib "libmx.lib"))) { throw "libmx.lib not found under $externLib" }

$outDir = Join-Path $projectRoot "build\mex"
New-Item -ItemType Directory -Force $outDir | Out-Null
$outFile = Join-Path $outDir "gskcec_eval.mexw64"
# Link into a temporary file and swap it in only on success: GNU ld deletes
# its output on a failed link, which would otherwise destroy a previously
# working bridge and block every MATLAB CEC experiment until a rebuild works.
$tmpFile = "$outFile.new"

# The bridge compiles the benchmark library sources directly so it never
# depends on a prior CMake build. F1..F15 are listed explicitly (as in
# CMakeLists.txt) rather than globbed: a directory listing that silently
# returns nothing (e.g. a tree copied with the Hidden attribute) would
# otherwise surface only as a confusing undefined-reference link error.
$sources = @(
    "benchmarks\cec_suite_cpp\cec_tools\src\mex_bridge\gskcec_eval_mex.cpp",
    "benchmarks\cec_suite_cpp\cec_tools\src\benchmark\data_loading.cpp",
    "benchmarks\cec_suite_cpp\cec_tools\src\benchmark\factory.cpp",
    "benchmarks\cec_suite_cpp\cec2013\src\cec2013_problem.cpp",
    "benchmarks\cec_suite_cpp\cec2013lsgo\src\Benchmarks.cpp",
    "benchmarks\cec_suite_cpp\cec2013lsgo\src\cec2013lsgo_problem.cpp",
    "benchmarks\cec_suite_cpp\cec2017\src\cec2017_problem.cpp",
    "benchmarks\cec_suite_cpp\cec2020\src\cec2020_problem.cpp",
    "benchmarks\cec_suite_cpp\cec2011\src\cec2011_problem.cpp",
    "benchmarks\cec_suite_cpp\cec2011\src\cec2011_problems_a.cpp",
    "benchmarks\cec_suite_cpp\cec2011\src\cec2011_problems_b.cpp",
    "benchmarks\cec_suite_cpp\cec2011\src\cec2011_problems_c.cpp"
) + (1..15 | ForEach-Object { "benchmarks\cec_suite_cpp\cec2013lsgo\src\F$_.cpp" })

$srcPaths = $sources | ForEach-Object { Join-Path $projectRoot $_ }
foreach ($s in $srcPaths) { if (-not (Test-Path $s)) { throw "Missing source: $s" } }

# Optimization: -O3 -march=native -funroll-loops -ffp-contract=off (the CMake
# GSKCEC_NATIVE flag set) -- ~1.15-1.36x faster than -O2, ctest-validated
# (12/12) and within the project's 1e-12 faithful-port tolerance.
# Reproducibility note: ANY rebuild with a current toolchain differs from the
# original committed-results binary by <=~4.3e-15 -- a libm/compiler-version
# artifact, NOT these flags (a plain -O2 rebuild shows the identical delta).
# -ffp-contract=off keeps -march's FMA hardware from adding any further drift.
# For a strict -O2 build instead, replace the "-O3", "-march=native",
# "-funroll-loops", "-ffp-contract=off" entries below with a single "-O2"
# (the rest of the argument list is unchanged).
$gxxArgs = @(
    "-std=c++20", "-O3", "-march=native", "-funroll-loops", "-ffp-contract=off", "-shared",
    "-static-libgcc", "-static-libstdc++",
    "-I", (Join-Path $projectRoot "benchmarks\cec_suite_cpp\cec_tools\include"),
    "-I", $externInc
) + $srcPaths + @(
    "-L", $externLib, "-lmx", "-lmex", "-lmat",
    "-o", $tmpFile
)
Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue

Write-Host "MATLAB root : $MatlabRoot"
Write-Host "g++         : $Gxx"
Write-Host "output      : $outFile"
& $Gxx @gxxArgs
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    throw "g++ failed with exit code $LASTEXITCODE (existing bridge, if any, left unchanged)"
}
try {
    Move-Item -LiteralPath $tmpFile -Destination $outFile -Force
} catch {
    throw "Built $tmpFile but could not replace $outFile (is it loaded in a MATLAB session? run 'clear mex' or close MATLAB, then retry): $($_.Exception.Message)"
}
Write-Host "gskcec_eval.mexw64 built successfully."
