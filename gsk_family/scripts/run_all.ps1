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
    [string]$SeedPolicy = "reference",
    [string]$RandGenerator = "threefry"
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
