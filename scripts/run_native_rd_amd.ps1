# Run actual Godot D3D12 native compute on the installed AMD GPU.
# Execute from the repository root with conda Python activated.
param(
    [int]$Width = 512,
    [int]$Height = 512,
    [int]$Warmup = 3,
    [int]$Samples = 12,
    [int]$Passes = 8,
    [int]$ResidentBatches = 1,
    [int]$StreamSlots = 0,
    [int]$ReadbackInterval = 1,
    [string]$Output = "native_rd_amd_profile.json",
    [string]$Baseline = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $root
try {
    $build = ".native-rd-windows-build"
    cmake -S native/vulkan_provider -B $build -G "Visual Studio 18 2026" -A x64 -DGODAULDRON_RD_ONLY=ON
    if ($LASTEXITCODE -ne 0) { throw "Native RD CMake configure failed" }
    cmake --build $build --config Release --parallel 4
    if ($LASTEXITCODE -ne 0) { throw "Native RD C++23 compilation failed" }
    $binary = Join-Path $build "Release/godauldron_native_rd_workload.dll"
    if (!(Test-Path $binary)) { throw "Native RD DLL absent: $binary" }
    # The installer refreshes the C++ DLL, descriptor and shared compositor
    # effect together, including when a prior native RD package is present.
    python native/rd_windows/install_package.py (Resolve-Path $binary).Path
    if ($LASTEXITCODE -ne 0) { throw "Native RD package installation failed" }
    $godot = ".engine/godot_console.exe"
    if (!(Test-Path $godot)) {
        python tools/fetch_preview.py --major 4 --platform win64.exe
        if ($LASTEXITCODE -ne 0) { throw "Godot Windows executable retrieval failed" }
    }
    & $godot --headless --path . --editor --import --quit
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }
    $destination = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else {
        Join-Path $root $Output
    }
    if ($StreamSlots -ne 0 -and ($StreamSlots -lt 2 -or $StreamSlots -gt 4)) {
        throw "StreamSlots must be 0 (serial) or 2..4 (autonomous)"
    }
    if ($ReadbackInterval -lt 1 -or $ReadbackInterval -gt 16) {
        throw "ReadbackInterval must be 1..16"
    }
    if ($ReadbackInterval -gt 1 -and $StreamSlots -eq 0) {
        throw "Checkpoint readbacks require -StreamSlots 2..4"
    }
    if ($ReadbackInterval -gt 1 -and
        ($Warmup -lt $StreamSlots * $ReadbackInterval -or
         $Warmup % $ReadbackInterval -ne 0 -or
         $Samples % $ReadbackInterval -ne 0)) {
        throw "Checkpoint mode requires warmup >= slots * interval, and both warmup and samples divisible by interval"
    }
    $script = if ($StreamSlots -gt 0) {
        "res://tests/native_rd_stream_profile.gd"
    } else {
        "res://tests/native_rd_hardware_profile.gd"
    }
    $gpuArgs = @("--path", ".", "--rendering-method", "forward_plus",
        "--rendering-driver", "d3d12", "--script", $script, "--",
        "--mode", "physical_amd", "--width", "$Width", "--height", "$Height",
        "--warmup", "$Warmup", "--samples", "$Samples", "--passes", "$Passes",
        "--resident_batches", "$ResidentBatches", "--output", "$destination")
    if ($StreamSlots -gt 0) { $gpuArgs += @("--slots", "$StreamSlots", "--readback_interval", "$ReadbackInterval") }
    & $godot @gpuArgs
    if ($LASTEXITCODE -ne 0) { throw "Physical AMD native GPU acceptance failed" }
    if ($StreamSlots -gt 0) {
        python tools/validate_native_rd_stream_profile.py $destination --mode physical_amd
        if ($LASTEXITCODE -ne 0) { throw "Sustained native GPU report validation failed" }
        Write-Host "Validated sustained native AMD throughput report: $destination"
    } else {
        python tools/validate_native_rd_profile.py $destination --mode physical_amd
        if ($LASTEXITCODE -ne 0) { throw "GPU report validation failed" }
        $analysisJson = [System.IO.Path]::ChangeExtension($destination, ".analysis.json")
        $analysisCsv = [System.IO.Path]::ChangeExtension($destination, ".csv")
        $analysisArgs = @("tools/analyze_native_rd_profile.py", $destination,
            "--json-output", $analysisJson, "--csv-output", $analysisCsv)
        if ($Baseline) { $analysisArgs += @("--baseline", $Baseline) }
        python @analysisArgs
        if ($LASTEXITCODE -ne 0) { throw "Native RD performance analysis failed" }
        Write-Host "Validated native AMD report: $destination"
        Write-Host "Profile analysis: $analysisJson"
        Write-Host "Per-batch measurements: $analysisCsv"
    }
} finally {
    Pop-Location
}
