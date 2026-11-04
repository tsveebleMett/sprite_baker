param(
    [ValidateSet('app', 'editor', 'test', 'render-test', 'coverage', 'all-tests')]
    [string]$Mode = 'app',
    [string]$Godot = $env:GODOT_BINARY
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
    $portable = Join-Path $projectRoot '.tools/godot/Godot_v4.6.1-stable_win64_console.exe'
    if (Test-Path -LiteralPath $portable) { $Godot = $portable }
    elseif ($env:GODOT_PATH) { $Godot = $env:GODOT_PATH }
    else {
        $candidate = Get-Command godot -ErrorAction SilentlyContinue
        if ($candidate) { $Godot = $candidate.Source }
    }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
    throw 'Godot 4.6.1 nicht gefunden. -Godot C:/Pfad/godot.exe angeben oder GODOT_BINARY setzen.'
}
$version = & $Godot --version 2>&1
if ($LASTEXITCODE -ne 0 -or "$version" -notmatch '^4\.[6-9]') {
    throw "Godot-Start fehlgeschlagen: $version. Eine offizielle Godot-4.6.1-Binary mit -Godot angeben."
}
Push-Location $projectRoot
try {
    if ($Mode -eq 'app') { & $Godot --path $projectRoot; exit $LASTEXITCODE }
    if ($Mode -eq 'editor') { & $Godot --editor --path $projectRoot; exit $LASTEXITCODE }
    $tests = @()
    if ($Mode -in @('test', 'all-tests')) {
        $tests += @('test_core', 'test_scene', 'test_export', 'test_compact', 'test_ui')
    }
    if ($Mode -in @('render-test', 'all-tests')) {
        $tests += @('test_render', 'test_render_quality', 'test_ui_render')
    }
    New-Item -ItemType Directory -Force '.tools/test-logs' | Out-Null
    foreach ($test in $tests) {
        $arguments = @('--path', $projectRoot, '--script', "tests/$test.gd")
        if ($test -notin @('test_render', 'test_render_quality', 'test_ui_render')) {
            $arguments = @('--headless') + $arguments
        } else { $arguments += @('--resolution', '1440x960') }
        $log = & $Godot @arguments 2>&1
        $resultCode = $LASTEXITCODE
        $log | Set-Content -Encoding utf8 ".tools/test-logs/$test.log"
        $log | Write-Output
        if ($resultCode -ne 0 -or ($log -join "`n") -match '(?m)^(SCRIPT ERROR|ERROR):') {
            throw "Test fehlgeschlagen: $test (Exit $resultCode)."
        }
    }
    if ($Mode -in @('coverage', 'all-tests')) {
        & python tests/core_coverage.py --godot $Godot
        if ($LASTEXITCODE -ne 0) { throw 'Coverage-Prüfung fehlgeschlagen.' }
    }
} finally { Pop-Location }
