$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$binlogDir = Join-Path $repoRoot 'BuildOutput\binlogs'
New-Item -ItemType Directory -Force -Path $binlogDir | Out-Null

$cppWinRTPackagesConfig = Join-Path $repoRoot 'src\XamlCompiler\Tests\RegressionProjects\Basic\CppWinRT\SimpleModules\packages.config'
[xml]$packagesConfig = Get-Content $cppWinRTPackagesConfig
$cppWinRTPackage = $packagesConfig.packages.package | Where-Object { $_.id -eq 'Microsoft.Windows.CppWinRT' }
if (-not $cppWinRTPackage) {
    throw 'Microsoft.Windows.CppWinRT was not found in the SimpleModules packages.config.'
}

$cppWinRTPackageDir = Join-Path $repoRoot ("packages\{0}.{1}" -f $cppWinRTPackage.id, $cppWinRTPackage.version)
if (-not (Test-Path $cppWinRTPackageDir)) {
    $nuget = Get-Command nuget.exe -ErrorAction Stop
    & $nuget.Source install $cppWinRTPackage.id -Version $cppWinRTPackage.version -OutputDirectory (Join-Path $repoRoot 'packages') -Source https://api.nuget.org/v3/index.json -NonInteractive
    if ($LASTEXITCODE -ne 0) {
        throw "NuGet restore for $($cppWinRTPackage.id) $($cppWinRTPackage.version) failed with exit code $LASTEXITCODE."
    }
}

$moduleProjects = @(
    'src\XamlCompiler\Tests\RegressionProjects\Basic\CppWinRT\SimpleModules\SimpleCppWinRTModules.vcxproj',
    'src\XamlCompiler\Tests\RegressionProjects\Features\StaticLibs\StaticControlsModuleLib\StaticControlsModuleLib.vcxproj',
    'src\XamlCompiler\Tests\RegressionProjects\Features\StaticLibs\StaticControlsModuleConsumer\StaticControlsModuleConsumer.vcxproj'
)

foreach ($relativeProject in $moduleProjects) {
    $project = Join-Path $repoRoot $relativeProject
    $name = [System.IO.Path]::GetFileNameWithoutExtension($project)
    & msbuild.exe $project /t:Build /p:Configuration=Debug /p:Platform=x64 /p:VisualStudioVersion=17.0 /p:UseXamlCompiler=true /p:SkipXamlCompilerProjectReferences=true /m:2 /ds:false "/binaryLogger:$binlogDir\$name.ModuleValidation.binlog"
    if ($LASTEXITCODE -ne 0) {
        throw "$name named-module regression build failed with exit code $LASTEXITCODE."
    }
}

$unitTestProject = Join-Path $repoRoot 'src\XamlCompiler\Tests\UnitTests\XamlCompilerUnitTests.csproj'
& msbuild.exe $unitTestProject /t:Build /restore /p:Configuration=Debug /p:Platform=x64 /p:VisualStudioVersion=17.0 '/p:RuntimeIdentifiers=win;win10-x64;win10-x86;win10-arm64' /p:DisableWarnForInvalidRestoreProjects=true /m:2 /ds:false "/binaryLogger:$binlogDir\XamlCompilerUnitTests.ModuleValidation.binlog"
if ($LASTEXITCODE -ne 0) {
    throw "XamlCompiler unit-test build failed with exit code $LASTEXITCODE."
}

if ($env:VSINSTALLDIR) {
    $vsTest = Join-Path $env:VSINSTALLDIR 'Common7\IDE\Extensions\TestPlatform\vstest.console.exe'
    if (Test-Path $vsTest) {
        $env:VSTEST_CONSOLE = $vsTest
    }
}

$runTests = Join-Path $repoRoot 'src\XamlCompiler\runtests.cmd'
& cmd.exe /d /c ('call "{0}" /config:amd64chk /platform:x64 /flavor:chk "/TestCaseFilter:FullyQualifiedName~UnitTests.CppWinRTModuleTests"' -f $runTests)
if ($LASTEXITCODE -ne 0) {
    throw "CppWinRTModuleTests failed with exit code $LASTEXITCODE."
}
