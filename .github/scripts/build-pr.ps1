param(
    [Parameter(Mandatory)] [string]$Flavor,
    [Parameter(Mandatory)] [string]$Platform,
    [Parameter(Mandatory)] [string]$Configuration
)

$ErrorActionPreference = 'Stop'

# init.cmd's UAC fallback fails non-interactively; ensure long-path support up front.
$lp = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
if ((Get-ItemProperty -Path $lp -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue).LongPathsEnabled -ne 1) {
    New-ItemProperty -Path $lp -Name 'LongPathsEnabled' -Value 1 -PropertyType DWord -Force | Out-Null
}

foreach ($v in 'ACTIONS_RUNTIME_TOKEN','ACTIONS_RUNTIME_URL','ACTIONS_RESULTS_URL','ACTIONS_CACHE_URL','ACTIONS_ID_TOKEN_REQUEST_TOKEN','ACTIONS_ID_TOKEN_REQUEST_URL','GITHUB_TOKEN') {
    Remove-Item "env:$v" -ErrorAction SilentlyContinue
}

$binlogDir = "BuildOutput\binlogs"
Write-Host "flavor=$Flavor platform=$Platform configuration=$Configuration"
if (-not (Test-Path $binlogDir)) { New-Item -ItemType Directory -Force -Path $binlogDir | Out-Null }

$commonArgs = "/restore /m /ds:false"

# The hosted image can contain both VS 2022 (17.x) and VS 2026 (18.x).
# WinUI's current OSS build is validated with VS 2022. Enter that developer
# prompt explicitly before init.cmd so DevCmd.cmd's broad "16.0 or later"
# vswhere query cannot silently select VS 18.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsInstall = & $vswhere -latest -version '[17.0,18.0)' -requires Microsoft.Component.MSBuild -property installationPath
if (-not $vsInstall) {
    throw 'Visual Studio 2022 / MSBuild 17.x is required for the OSS PR build.'
}
$vsDevCmd = Join-Path $vsInstall 'Common7\Tools\VsDevCmd.bat'
$devArch = switch ($Platform.ToLowerInvariant()) {
    'x86' { 'x86' }
    'x64' { 'amd64' }
    'arm64' { 'arm64' }
    default { throw "Unsupported PR build platform '$Platform'." }
}

# Build the XAML compiler from source. XamlCompilerPrerequisites.sln also builds
# GenXbf (via the BuildGenXbfForMSBuild project it contains), so no separate step is needed.
$prereqSteps = @(
    "msbuild XamlCompilerPrerequisites.sln /p:Platform=$Platform /p:Configuration=$Configuration $commonArgs /binaryLogger:$binlogDir\XamlCompilerPrerequisites.$Platform.$Configuration.binlog"
)

$sequence = $prereqSteps + @(
    "msbuild Microsoft.UI.Xaml-Product.sln                       /p:Platform=$Platform /p:Configuration=$Configuration $commonArgs /binaryLogger:$binlogDir\Microsoft.UI.Xaml-Product.$Platform.$Configuration.binlog",
    "msbuild controls\dev\dll\Microsoft.UI.Xaml.Controls.vcxproj /p:Platform=$Platform /p:Configuration=$Configuration $commonArgs /binaryLogger:$binlogDir\Microsoft.UI.Xaml.Controls.$Platform.$Configuration.binlog"
)

# C++/WinRT 3.x named-module validation runs in a separate VS2026/v145 job.
# Keep this product matrix on the repository's VS2022 baseline.

$sequence += "pack.component.cmd"

$quote = [char]34
$chain = "call $quote$vsDevCmd$quote -no_logo -arch=$devArch -host_arch=amd64" +
    " && init.cmd $Flavor /nopgo" +
    " && " + ($sequence -join " && ")
Write-Host $chain

cmd /c $chain
$cmdExit = $LASTEXITCODE
if ($cmdExit -ne 0) {
    Write-Host "::error::Build chain exited with code $cmdExit."
    exit $cmdExit
}
