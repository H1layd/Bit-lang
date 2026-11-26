# Run in a fresh private directory containing thread-handles.exe.
$ErrorActionPreference = 'Stop'
$ready = Join-Path $PSScriptRoot 'thread-handles-ready'
if (Test-Path $ready) { throw 'Use a fresh test directory' }
$process = Start-Process -PassThru -FilePath (Join-Path $PSScriptRoot 'thread-handles.exe') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
try {
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path $ready)) {
        if ($process.HasExited) { throw "Test process exited early: $($process.ExitCode)" }
        if ((Get-Date) -gt $deadline) { throw 'Timed out waiting for thread test' }
        Start-Sleep -Milliseconds 100
        $process.Refresh()
    }
    $process.Refresh()
    $handles = $process.HandleCount
    Write-Output "handles_after_1000_threads=$handles"
    if ($handles -gt 256) { throw 'Thread handles did not get closed after wait' }
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id }
}
