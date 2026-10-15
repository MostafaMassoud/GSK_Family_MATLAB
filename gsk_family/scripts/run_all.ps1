# Builds the C++ tools with CMake, runs ctest, then runs gsk_run on each config.
#
# Usage:
#   powershell -File scripts\run_all.ps1 [-Full] [-Configs <yml>,...] [options]
#
# Runs from the project root. By default builds into build\ (MinGW Makefiles,
# Release; change with -BuildDir, -Generator, -BuildType) and runs
# configs\smoke.yml. -Full runs smoke, all_cec2017, all_cec2011 and
# agsk_cec2020 unless -Configs is given. -SkipBuild and -SkipTests skip those
# steps. -DryRun, -Overwrite, -NoVerify, -Matlab, -Output, -Reference,
# -SeedPolicy and -RandGenerator are passed to gsk_run.
# Stops with an error if gsk_run.exe or a config is missing, or at the first
# config whose gsk_run fails. The cmake and ctest exit codes are not checked.
param(
    [string]$BuildDir = "build",
    [string]$Generator = "MinGW Makefiles",
    [string]$BuildType = "Release",
    [string[]]$Configs = @("configs\smoke.yml"),
    [switch]$Full,
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [switch]$DryRun,
    [switch]$Overwrite,
    [switch]$NoVerify,
    [string]$Matlab = "",
    [string]$Output = "",
    [string]$Reference = "",
    # Empty = use each config's seed_policy / rand_generator (gsk_run uses
    # reference + threefry when a config omits them). Set a value only to
    # override every config.
    [string]$SeedPolicy = "",
    [string]$RandGenerator = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
Push-Location $projectRoot
try {
    if ($Full -and -not $PSBoundParameters.ContainsKey("Configs")) {
        $Configs = @(
            "configs\smoke.yml",
            "configs\all_cec2017.yml",
            "configs\all_cec2011.yml",
            "configs\agsk_cec2020.yml"
        )
    }

    if (-not $SkipBuild) {
        cmake -S . -B $BuildDir -G $Generator -DCMAKE_BUILD_TYPE=$BuildType
        cmake --build $BuildDir -j
    }

    if (-not $SkipTests) {
        ctest --test-dir $BuildDir --output-on-failure
    }

    $runner = Join-Path $BuildDir "gsk_run.exe"
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "gsk_run executable not found at $runner; build first or pass -BuildDir."
    }

    foreach ($config in $Configs) {
        if (-not (Test-Path -LiteralPath $config)) {
            throw "Config not found: $config"
        }

        $args = @("--config", $config, "--root", ".")
        if ($DryRun) { $args += "--dry-run" }
        if ($Overwrite) { $args += "--overwrite" }
        if ($NoVerify) { $args += "--no-verify" }
        if ($Matlab -ne "") { $args += @("--matlab", $Matlab) }
        if ($Output -ne "") { $args += @("--output", $Output) }
        if ($Reference -ne "") { $args += @("--reference", $Reference) }
        if ($SeedPolicy -ne "") { $args += @("--seed-policy", $SeedPolicy) }
        if ($RandGenerator -ne "") { $args += @("--rand-generator", $RandGenerator) }

        Write-Host "run_all: $runner $($args -join ' ')"
        & $runner @args
        if ($LASTEXITCODE -ne 0) {
            throw "gsk_run failed for $config with exit code $LASTEXITCODE"
        }
    }
} finally {
    Pop-Location
}
