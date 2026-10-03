# Load the repo-root .env file into the current PowerShell session.
# Usage (note the leading dot + space, which runs it in the current scope):
#   . .\00_setup\load_env.ps1
$envFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
if (-not (Test-Path $envFile)) {
    Write-Error "No .env found at $envFile. Run: copy 00_setup\.env.example .env"
    return
}
$count = 0
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }
    $name = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
    Set-Item -Path "Env:$name" -Value $value
    $count++
}
Write-Host "Loaded $count variables from .env"
