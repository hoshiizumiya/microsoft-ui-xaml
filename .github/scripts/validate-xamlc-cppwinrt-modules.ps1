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

function Invoke-XamlModuleBuild {
    param(
        [Parameter(Mandatory)] [string]$RelativeProject,
        [Parameter(Mandatory)] [string]$LogName,
        [string[]]$ExtraProperties = @()
    )

    $project = Join-Path $repoRoot $RelativeProject
    $arguments = @(
        $project,
        '/t:Build',
        '/p:Configuration=Debug',
        '/p:Platform=x64',
        '/p:VisualStudioVersion=17.0',
        '/p:UseXamlCompiler=true',
        '/p:SkipXamlCompilerProjectReferences=true',
        '/m:2',
        '/ds:false',
        "/binaryLogger:$binlogDir\$LogName.binlog"
    ) + $ExtraProperties

    & msbuild.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$LogName failed with exit code $LASTEXITCODE."
    }
}

$simpleModules = 'src\XamlCompiler\Tests\RegressionProjects\Basic\CppWinRT\SimpleModules\SimpleCppWinRTModules.vcxproj'
$staticProvider = 'src\XamlCompiler\Tests\RegressionProjects\Features\StaticLibs\StaticControlsModuleLib\StaticControlsModuleLib.vcxproj'
$staticConsumer = 'src\XamlCompiler\Tests\RegressionProjects\Features\StaticLibs\StaticControlsModuleConsumer\StaticControlsModuleConsumer.vcxproj'

# Exercise the same project across incremental state transitions. CppWinRTBuildModule is
# passed as a global property for the mode-switch builds so it overrides the project's
# module-mode default and forces XamlC's FeatureControlFlags/saved state to invalidate.
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.CleanModule'
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.NoChangeModule'

$mainPage = Join-Path (Split-Path (Join-Path $repoRoot $simpleModules)) 'MainPage.xaml'
Start-Sleep -Seconds 1
(Get-Item $mainPage).LastWriteTime = Get-Date
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.OnePageChanged'

# Remove a Page without cleaning. The old EmptyPage.xaml.g.h must disappear; otherwise
# cppwinrt's generated EmptyPage.g.h __has_include bridge finds the stale file and imports
# an Application_Xaml umbrella that no longer exports the EmptyPage partition.
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.PageRemoved' @('/p:IncludeIncrementalEmptyPage=false')
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.PageAddedBack' @('/p:IncludeIncrementalEmptyPage=true')

Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.HeaderSwitch' @('/p:CppWinRTBuildModule=false')
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.ModuleSwitchBack' @('/p:CppWinRTBuildModule=true')

# The provider is also built once with type-info code generation disabled. This validates
# that the primary Application_Xaml interface does not retain a stale :XamlTypeInfo export.
Invoke-XamlModuleBuild $staticProvider 'StaticControlsModuleLib.Module'
Invoke-XamlModuleBuild $staticProvider 'StaticControlsModuleLib.NoTypeInfo' @('/p:XamlCodeGenerationControlFlags=NoTypeInfoCodeGen')
Invoke-XamlModuleBuild $staticConsumer 'StaticControlsModuleConsumer.CrossProject'

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
