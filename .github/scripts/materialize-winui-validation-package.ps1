param(
    [string]$PackageStore,
    [string]$PackagesDirectory
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if (-not $PackageStore) {
    $PackageStore = Join-Path $repoRoot 'PackageStore'
}
if (-not $PackagesDirectory) {
    $PackagesDirectory = Join-Path $repoRoot 'packages'
}

$versionsProps = Join-Path $repoRoot 'eng\Versions.props'
[xml]$versions = Get-Content -LiteralPath $versionsProps
$winUIVersionNode = @($versions.Project.PropertyGroup.WinUIVersion | Where-Object { $_.'#text' }) | Select-Object -First 1
if (-not $winUIVersionNode) {
    throw "Unable to determine WinUIVersion from '$versionsProps'."
}

$version = [string]$winUIVersionNode.'#text'
$packageId = 'Microsoft.WindowsAppSDK.WinUI'
$nupkg = Join-Path $PackageStore "$packageId.$version.nupkg"
if (-not (Test-Path -LiteralPath $nupkg)) {
    $available = @(Get-ChildItem -LiteralPath $PackageStore -Filter "$packageId.*.nupkg" -File -ErrorAction SilentlyContinue)
    throw "Expected '$nupkg' was not found. Available WinUI packages: $($available.Name -join ', ')"
}

$destination = Join-Path $PackagesDirectory "$packageId.$version"
$requiredProps = Join-Path $destination 'build\native\Microsoft.WindowsAppSDK.WinUI.props'
$requiredTargets = Join-Path $destination 'build\native\Microsoft.WindowsAppSDK.WinUI.targets'

if (-not (Test-Path -LiteralPath $requiredProps) -or -not (Test-Path -LiteralPath $requiredTargets)) {
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $destination)
}

if (-not (Test-Path -LiteralPath $requiredProps) -or -not (Test-Path -LiteralPath $requiredTargets)) {
    throw "WinUI validation package did not contain the expected native build imports under '$destination'."
}

Write-Host "Materialized $packageId $version at '$destination'."
