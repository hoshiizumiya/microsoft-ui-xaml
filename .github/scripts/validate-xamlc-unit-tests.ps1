param(
    [string]$VisualStudioVersion = '17.0',
    [string]$WindowsSdkVersion = '10.0.26100.0',
    [string]$TestCaseFilter,
    [switch]$SkipRegressionBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resultsDir = Join-Path $repoRoot 'BuildOutput\TestResults\XamlCompiler'
$binlogDir = Join-Path $repoRoot 'BuildOutput\binlogs'
if (-not $env:EnvironmentInitialized -or -not $env:BuildOutputRoot -or -not $env:_BuildArch -or -not $env:_BuildType) {
    throw 'Run init.cmd in the current developer environment before unit validation.'
}
$flavor = "$($env:_BuildArch)$($env:_BuildType)"
$testDir = Join-Path $env:BuildOutputRoot "$flavor\src\XamlCompiler\Tests\UnitTests\XamlCompilerUnitTests"
New-Item -ItemType Directory -Force -Path $resultsDir, $binlogDir | Out-Null
$vsTest = Join-Path $env:VSINSTALLDIR 'Common7\IDE\Extensions\TestPlatform\vstest.console.exe'
if (-not (Test-Path $vsTest)) {
    throw "VSTest was not found at '$vsTest'."
}

function Restore-XamlCompilerNativeDependencies {
    # The rebased upstream native fixtures import WinAppSDK component props/targets through
    # legacy packages.config-style paths (packages\Id.Version\...). The component restore
    # project is PackageReference-based, so NuGet materializes its direct and transitive
    # closure as packages\id\version\... instead. Restore once, then mirror that resolved
    # closure into the legacy layout expected by the native test preamble/postamble.
    $componentDependencies = Join-Path $repoRoot 'eng\RestoreComponentDependencies.csproj'
    $packagesDirectory = Join-Path $repoRoot 'packages'
    $nugetConfig = Join-Path $repoRoot 'nuget.config'
    $nuget = Get-Command nuget.exe -ErrorAction Stop

    & $nuget.Source restore $componentDependencies -ConfigFile $nugetConfig -PackagesDirectory $packagesDirectory -NonInteractive
    if ($LASTEXITCODE -ne 0) {
        throw "Component dependency restore failed with exit code $LASTEXITCODE."
    }

    $assetsPath = Join-Path (Split-Path $componentDependencies) 'obj\project.assets.json'
    if (-not (Test-Path $assetsPath -PathType Leaf)) {
        throw "Component dependency restore did not produce '$assetsPath'."
    }

    $assets = Get-Content -LiteralPath $assetsPath -Raw | ConvertFrom-Json
    $packageRoots = @($assets.packageFolders.PSObject.Properties.Name)
    if ($packageRoots.Count -eq 0) {
        throw 'Component dependency assets did not declare any package folders.'
    }

    $materialized = 0
    foreach ($libraryProperty in $assets.libraries.PSObject.Properties) {
        $library = $libraryProperty.Value
        if ($library.type -ne 'package') {
            continue
        }

        $identity = $libraryProperty.Name
        $separator = $identity.LastIndexOf('/')
        if ($separator -le 0 -or $separator -eq $identity.Length - 1) {
            throw "Unexpected package identity '$identity' in component dependency assets."
        }

        $packageId = $identity.Substring(0, $separator)
        $packageVersion = $identity.Substring($separator + 1)
        $relativePath = $library.path
        if (-not $relativePath) {
            $relativePath = "$($packageId.ToLowerInvariant())/$($packageVersion.ToLowerInvariant())"
        }

        $sourcePath = $null
        foreach ($packageRoot in $packageRoots) {
            $candidate = Join-Path $packageRoot ($relativePath -replace '/', '\')
            if (Test-Path $candidate -PathType Container) {
                $sourcePath = $candidate
                break
            }
        }
        if (-not $sourcePath) {
            throw "Resolved component package '$identity' was not found under: $($packageRoots -join '; ')"
        }

        $legacyPath = Join-Path $packagesDirectory "$packageId.$packageVersion"
        if (-not (Test-Path $legacyPath -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $legacyPath | Out-Null
            Copy-Item -Path (Join-Path $sourcePath '*') -Destination $legacyPath -Recurse -Force
            $materialized++
        }
    }

    Write-Host "Materialized $materialized component package(s) into legacy packages.config layout."
}

function Invoke-TestBuild([string]$RelativeProject, [string[]]$ExtraProperties = @()) {
    $project = Join-Path $repoRoot $RelativeProject
    $name = [IO.Path]::GetFileNameWithoutExtension($project)
    $arguments = @(
        $project, '/restore', '/t:Build', '/p:Configuration=Debug', '/p:Platform=x64',
        "/p:VisualStudioVersion=$VisualStudioVersion",
        "/p:TargetPlatformVersion=$WindowsSdkVersion",
        "/p:WindowsSdkTargetPlatformVersion=$WindowsSdkVersion",
        "/p:WindowsTargetPlatformVersion=$WindowsSdkVersion",
        '/p:UseXamlCompiler=true', '/p:SkipXamlCompilerProjectReferences=true',
        '/p:IncludeXamlDlls=true', '/p:SpectreMitigation=false',
        '/p:DisableWarnForInvalidRestoreProjects=true', '/m:2', '/ds:false',
        "/binaryLogger:$binlogDir\$name.UnitValidation.binlog"
    ) + $ExtraProperties
    & msbuild.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$name test build failed with exit code $LASTEXITCODE."
    }
}

Restore-XamlCompilerNativeDependencies

if ($SkipRegressionBuild) {
    # The focused filter consumes the already-built x64chk WinUI product projection. Rebuilding
    # Microsoft.WinUI.csproj here would re-enter WinUI's source-generation graph even though this
    # validation job only restores product artifacts, not the full intermediate MIDL tree.
    $productDir = Join-Path $env:BuildOutputRoot "$flavor\Product"
    $projects = @(
        'src\XamlCompiler\Tests\UnitTests\LibManagedDllSatellite\LibManagedDllSatellite.csproj',
        'src\XamlCompiler\Tests\UnitTests\LibManagedDll\LibManagedDll.csproj',
        'src\XamlCompiler\Tests\UnitTests\LibManagedWinmd\LibManagedWinmd.csproj',
        'src\XamlCompiler\Tests\UnitTests\XamlCompilerProxies\XamlCompilerProxies.csproj',
        'src\XamlCompiler\Tests\UnitTests\XamlCompilerUnitTests.csproj'
    )
    foreach ($project in $projects) {
        Invoke-TestBuild $project @('/p:BuildProjectReferences=false', "/p:PublicMUXDir=$productDir\")
    }
}
else {
    # Upstream #11837 re-enabled generated-code comparisons. Build their inputs too;
    # executing the full suite without the regression output would invalidate those tests.
    Invoke-TestBuild 'src\XamlCompiler\XamlCompilerTests.sln' @('/p:PlatformToolset=v143')
}

foreach ($required in @('UnitTests.dll', 'XamlCompilerUnitTests.payload.complete')) {
    if (-not (Test-Path (Join-Path $testDir $required))) {
        throw "Required upstream test payload file is missing: $required"
    }
}

function Invoke-TestCommand([string[]]$Arguments, [string]$LogName) {
    # Windows PowerShell otherwise promotes native stderr to a terminating error before
    # VSTest's exit code and TRX summary are captured. Restore the preference immediately.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $vsTest @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $resultsDir $LogName) | Out-Host
        $commandExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return $commandExit
}

$settings = Join-Path $repoRoot 'src\XamlCompiler\Tests\UnitTests\test.runsettings'
$assembly = Join-Path $testDir 'UnitTests.dll'
$discoveryExit = Invoke-TestCommand @($assembly, "/Settings:$settings", '/ListTests') 'discovered-tests.txt'
if ($discoveryExit -ne 0) {
    throw "Unit discovery failed with exit code $discoveryExit."
}
$arguments = @($assembly, "/Settings:$settings", "/ResultsDirectory:$resultsDir", '/Logger:trx;LogFileName=XamlCompiler.trx')
if ($TestCaseFilter) {
    $arguments += "/TestCaseFilter:$TestCaseFilter"
}
$testExit = Invoke-TestCommand $arguments 'vstest.log'
$trxPath = Join-Path $resultsDir 'XamlCompiler.trx'
if (-not (Test-Path $trxPath)) {
    throw 'VSTest did not produce XamlCompiler.trx.'
}
[xml]$trx = Get-Content -LiteralPath $trxPath
$counters = $trx.TestRun.ResultSummary.Counters
if (-not $counters -or [int]$counters.executed -eq 0) {
    throw 'VSTest did not execute any tests.'
}
$summary = "total=$($counters.total) executed=$($counters.executed) passed=$($counters.passed) failed=$($counters.failed) notExecuted=$($counters.notExecuted)"
$summary | Set-Content -Path (Join-Path $resultsDir 'summary.txt')
Write-Host $summary
if ($testExit -ne 0 -or [int]$counters.failed -gt 0) {
    throw "XamlCompiler unit suite failed: $summary"
}
