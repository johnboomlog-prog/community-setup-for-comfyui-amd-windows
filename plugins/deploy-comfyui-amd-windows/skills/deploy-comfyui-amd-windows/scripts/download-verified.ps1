[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][uri]$Uri,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$Sha256,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($Destination)
$parent = Split-Path -Parent $target
if (-not $parent) { throw 'Destination must include a parent directory.' }
if ((Test-Path -LiteralPath $target) -and -not $Force) { throw "Destination exists; use -Force only after confirming replacement: $target" }
if (-not $PSCmdlet.ShouldProcess($target, "Download $Uri and verify SHA-256")) { return }

New-Item -ItemType Directory -Path $parent -Force | Out-Null
$partial = "$target.partial-$PID"
try {
    Invoke-WebRequest -Uri $Uri -OutFile $partial -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
    if ($actual -ne $Sha256.ToUpperInvariant()) { throw "SHA-256 mismatch. Expected $Sha256, got $actual" }
    Move-Item -LiteralPath $partial -Destination $target -Force:$Force
    [ordered]@{ path = $target; sha256 = $actual; source = $Uri.AbsoluteUri; verified = $true } | ConvertTo-Json
} finally {
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
}

