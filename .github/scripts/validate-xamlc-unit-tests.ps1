param(
    [string]$VisualStudioVersion = '17.0',
    [string]$WindowsSdkVersion = '10.0.26100.0',
    [string]$TestCaseFilter
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resultsDir = Join-Path $repoRoot 'BuildOutput\TestResults\XamlCompiler'
$binlogDir = Join-Path $repoRoot 'BuildOutput\binlogs'
$testsRoot = Join-Path $repoRoot 'src\XamlCompiler\Tests'
$productDir = Join-Path $repoRoot 'BuildOutput\bin\amd64chk\Product'
$compilerDir = Join-Path $productDir 'Microsoft.UI.Xaml.Markup.Compiler\net472'
$unitObjDir = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\src\XamlCompiler\Tests\UnitTests'
$stageDir = Join-Path $testsRoot 'UnitTests\UnitTestingBin'

New-Item -ItemType Directory -Force -Path $resultsDir, $binlogDir, $stageDir | Out-Null
$vsTest = Join-Path $env:VSINSTALLDIR 'Common7\IDE\Extensions\TestPlatform\vstest.console.exe'
if (-not (Test-Path $vsTest)) {
    throw "VSTest was not found at '$vsTest'. Enter a Visual Studio developer environment first."
}
if (-not (Test-Path (Join-Path $compilerDir 'Microsoft.UI.Xaml.Markup.Compiler.dll'))) {
    throw 'Build or restore the x64 Debug XamlCompiler product prerequisites before running unit tests.'
}

# Build test assemblies against the existing product artifacts, without rebuilding WinUI.
$projects = @(
    'UnitTests\LibManagedDllSatellite\LibManagedDllSatellite.csproj',
    'UnitTests\LibManagedDll\LibManagedDll.csproj',
    'UnitTests\LibManagedWinmd\LibManagedWinmd.csproj',
    'XamlCompilerProxies\XamlCompilerProxies.csproj',
    'UnitTests\XamlCompilerUnitTests.csproj'
)
foreach ($relativeProject in $projects) {
    $project = Join-Path $testsRoot $relativeProject
    $name = [IO.Path]::GetFileNameWithoutExtension($project)
    $arguments = @(
        $project, '/restore', '/t:Build', '/p:Configuration=Debug', '/p:Platform=x64',
        "/p:VisualStudioVersion=$VisualStudioVersion",
        "/p:TargetPlatformVersion=$WindowsSdkVersion",
        "/p:WindowsSdkTargetPlatformVersion=$WindowsSdkVersion",
        '/p:TargetPlatformMinVersion=10.0.17763.0',
        "/p:PublicMUXDir=$productDir\",
        '/p:BuildProjectReferences=false',
        '/p:RuntimeIdentifiers=win;win10-x64;win10-x86;win10-arm64',
        '/p:DisableWarnForInvalidRestoreProjects=true', '/m:2', '/ds:false',
        "/binaryLogger:$binlogDir\$name.UnitValidation.binlog"
    )
    & msbuild.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$name unit-test prerequisite build failed with exit code $LASTEXITCODE."
    }
}

function Copy-TestFile([string]$Source, [string]$DestinationName) {
    if (-not (Test-Path $Source -PathType Leaf)) {
        throw "Required unit-test dependency is missing: $Source"
    }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $stageDir $DestinationName) -Force
}

Copy-Item -Path (Join-Path $unitObjDir 'XamlCompilerUnitTests\*') -Destination $stageDir -Recurse -Force
Copy-Item -Path (Join-Path $compilerDir '*') -Destination $stageDir -Recurse -Force
Copy-TestFile (Join-Path $unitObjDir 'LibManagedDllSatellite\LibManagedDllSatellite\LibManagedDllSatellite.dll') 'LibManagedDllSatellite.dll'
Copy-TestFile (Join-Path $unitObjDir 'LibManagedDll\LibManagedDll\LibManagedDll.dll') 'LibManagedDll.dll'
Copy-TestFile (Join-Path $unitObjDir 'LibManagedWinmd\LibManagedWinmd\LibManagedWinmd.winmdobj') 'LibManagedWinmd.dll'
Copy-TestFile (Join-Path $unitObjDir 'LibManagedWinmd\LibManagedWinmd\LibManagedWinmd.winmd') 'LibManagedWinmd.winmd'
Copy-TestFile (Join-Path $productDir 'Microsoft.UI.Xaml.winmd') 'Microsoft.UI.Xaml.winmd'
Copy-TestFile (Join-Path $productDir 'Microsoft.UI.winmd') 'Microsoft.UI.winmd'
Copy-TestFile (Join-Path $repoRoot 'BuildOutput\bin\GenXbf\x64\GenXbf.dll') 'GenXbf.dll'
Copy-TestFile (Join-Path $testsRoot 'UnitTests\test.runsettings') 'test.runsettings'
foreach ($dependency in 'UnitTests.dll', 'Win8Xaml.CompilerProxies.dll', 'Microsoft.UI.Xaml.Markup.Compiler.dll') {
    if (-not (Test-Path (Join-Path $stageDir $dependency))) {
        throw "Unit-test staging did not produce $dependency."
    }
}

Push-Location $stageDir
try {
    & $vsTest 'UnitTests.dll' '/ListTests' '/Platform:x64' 2>&1 |
        Tee-Object -FilePath (Join-Path $resultsDir 'discovered-tests.txt')
    if ($LASTEXITCODE -ne 0) {
        throw "XamlCompiler test discovery failed with exit code $LASTEXITCODE."
    }

    $trxPath = Join-Path $resultsDir 'XamlCompiler.trx'
    if (Test-Path $trxPath) {
        Remove-Item -LiteralPath $trxPath
    }
    $arguments = @('UnitTests.dll', '/Settings:test.runsettings', '/Platform:x64',
        "/ResultsDirectory:$resultsDir", '/Logger:trx;LogFileName=XamlCompiler.trx')
    if ($TestCaseFilter) {
        $arguments += "/TestCaseFilter:$TestCaseFilter"
    }
    & $vsTest @arguments 2>&1 | Tee-Object -FilePath (Join-Path $resultsDir 'execution.txt')
    $testExitCode = $LASTEXITCODE
    if (-not (Test-Path $trxPath)) {
        throw 'VSTest did not produce an XamlCompiler TRX result.'
    }
    [xml]$trx = Get-Content -LiteralPath $trxPath
    $counters = $trx.TestRun.ResultSummary.Counters
    Write-Host "XamlCompiler results: total=$($counters.total) executed=$($counters.executed) passed=$($counters.passed) failed=$($counters.failed) notExecuted=$($counters.notExecuted)"
    if ([int]$counters.executed -eq 0) {
        throw 'VSTest executed zero XamlCompiler tests.'
    }
    if ($testExitCode -ne 0 -or [int]$counters.failed -ne 0) {
        throw "XamlCompiler unit tests failed with exit code $testExitCode. See $trxPath."
    }
}
finally {
    Pop-Location
}
