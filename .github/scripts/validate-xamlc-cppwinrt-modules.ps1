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
        [string[]]$ExtraProperties = @(),
        [string]$Target = 'Build'
    )

    $project = Join-Path $repoRoot $RelativeProject
    $arguments = @(
        $project,
        "/t:$Target",
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

$simpleObjRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\src\XamlCompiler\Tests\RegressionProjects\Basic\CppWinRT\SimpleModules'
$mainPageModuleHeaders = @(Get-ChildItem -Path $simpleObjRoot -Filter 'MainPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($mainPageModuleHeaders.Count -eq 0) {
    throw 'SimpleModules did not generate MainPage.xaml.g.h.'
}
$requiredPageProjectionImports = @(
    'export import winrt.Simple.Models;',
    'export import winrt.Simple.Targets;'
)
foreach ($requiredImport in $requiredPageProjectionImports) {
    $found = $false
    foreach ($header in $mainPageModuleHeaders) {
        if (Select-String -Path $header.FullName -SimpleMatch $requiredImport -Quiet) {
            $found = $true
            break
        }
    }
    if (-not $found) {
        throw "MainPage XAML partition did not export required x:Bind projection dependency: $requiredImport"
    }
}

Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.NoChangeModule'

$mainPage = Join-Path (Split-Path (Join-Path $repoRoot $simpleModules)) 'MainPage.xaml'
Start-Sleep -Seconds 1
(Get-Item $mainPage).LastWriteTime = Get-Date
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.OnePageChanged'

# Remove a Page without cleaning. The old EmptyPage.xaml.g.h must disappear; otherwise
# cppwinrt's generated EmptyPage.g.h __has_include bridge finds the stale file and imports
# an Application_Xaml umbrella that no longer exports the EmptyPage partition.
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.PageRemoved' @('/p:IncludeIncrementalEmptyPage=false')

$staleEmptyPageHeaders = @(Get-ChildItem -Path $simpleObjRoot -Filter 'EmptyPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($staleEmptyPageHeaders.Count -ne 0) {
    throw "Removed XAML Page left a stale EmptyPage.xaml.g.h: $($staleEmptyPageHeaders.FullName -join '; ')"
}

Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.PageAddedBack' @('/p:IncludeIncrementalEmptyPage=true')
$restoredEmptyPageHeaders = @(Get-ChildItem -Path $simpleObjRoot -Filter 'EmptyPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($restoredEmptyPageHeaders.Count -eq 0) {
    throw 'Restoring EmptyPage.xaml did not regenerate EmptyPage.xaml.g.h.'
}

# NoPageCodeGen is a Pass1 code-generation mode, so validate its module partition
# contract without compiling application sources that intentionally depend on Page
# InitializeComponent output.
Invoke-XamlModuleBuild -RelativeProject $simpleModules -LogName 'SimpleCppWinRTModules.NoPagePass1' -Target 'MarkupCompilePass1' -ExtraProperties @('/p:XamlCodeGenerationControlFlags=NoPageCodeGen')

$simplePrimaryHeaders = @(Get-ChildItem -Path $simpleObjRoot -Filter 'XamlBindingInfo.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($simplePrimaryHeaders.Count -eq 0) {
    throw 'SimpleModules did not generate XamlBindingInfo.xaml.g.h.'
}
foreach ($header in $simplePrimaryHeaders) {
    if (-not (Select-String -Path $header.FullName -SimpleMatch 'export import :Simple.App;' -Quiet)) {
        throw "NoPageCodeGen dropped the App partition from $($header.FullName)."
    }
    if (Select-String -Path $header.FullName -SimpleMatch 'export import :Simple.MainPage;' -Quiet) {
        throw "NoPageCodeGen retained the MainPage partition in $($header.FullName)."
    }
    if (Select-String -Path $header.FullName -SimpleMatch 'export import :Simple.EmptyPage;' -Quiet) {
        throw "NoPageCodeGen retained the EmptyPage partition in $($header.FullName)."
    }
}

$noPageAppHeaders = @(Get-ChildItem -Path $simpleObjRoot -Filter 'App.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
$noPageMainPageHeaders = @(Get-ChildItem -Path $simpleObjRoot -Filter 'MainPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
$noPageEmptyPageHeaders = @(Get-ChildItem -Path $simpleObjRoot -Filter 'EmptyPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($noPageAppHeaders.Count -eq 0) {
    throw 'NoPageCodeGen removed the App XAML code output.'
}
if ($noPageMainPageHeaders.Count -ne 0 -or $noPageEmptyPageHeaders.Count -ne 0) {
    throw 'NoPageCodeGen left stale non-Application .xaml.g.h outputs on disk.'
}

# Switching the code-generation flags back to their default must invalidate saved
# state again and restore the Page partitions.
Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.PageCodeGenRestored'
foreach ($header in $simplePrimaryHeaders) {
    foreach ($partition in @(':Simple.App;', ':Simple.MainPage;', ':Simple.EmptyPage;')) {
        if (-not (Select-String -Path $header.FullName -SimpleMatch "export import $partition" -Quiet)) {
            throw "Restoring Page codegen did not restore partition $partition in $($header.FullName)."
        }
    }
}
foreach ($pageHeaderName in @('App.xaml.g.h', 'MainPage.xaml.g.h', 'EmptyPage.xaml.g.h')) {
    if (@(Get-ChildItem -Path $simpleObjRoot -Filter $pageHeaderName -File -Recurse -ErrorAction SilentlyContinue).Count -eq 0) {
        throw "Restoring Page codegen did not regenerate $pageHeaderName."
    }
}

$moduleIfcsBeforeHeaderSwitch = @(Get-ChildItem -Path $simpleObjRoot -Filter '*.ifc' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\XamlModules*' })
if ($moduleIfcsBeforeHeaderSwitch.Count -eq 0) {
    throw 'Module-mode build did not produce any XAML IFCs before the header-mode transition.'
}

Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.HeaderSwitch' @('/p:CppWinRTBuildModule=false')
$moduleIfcsInHeaderMode = @(Get-ChildItem -Path $simpleObjRoot -Filter '*.ifc' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\XamlModules*' })
if ($moduleIfcsInHeaderMode.Count -ne 0) {
    throw "Header-mode build left stale XAML IFCs: $($moduleIfcsInHeaderMode.FullName -join '; ')"
}

Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.ModuleSwitchBack' @('/p:CppWinRTBuildModule=true')
$moduleIfcsAfterSwitchBack = @(Get-ChildItem -Path $simpleObjRoot -Filter '*.ifc' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\XamlModules*' })
if ($moduleIfcsAfterSwitchBack.Count -eq 0) {
    throw 'Switching back to module mode did not regenerate XAML IFCs.'
}

# The provider is also built once with type-info code generation disabled. This validates
# that the primary Application_Xaml interface does not retain a stale :XamlTypeInfo export.
Invoke-XamlModuleBuild $staticProvider 'StaticControlsModuleLib.Module'
Invoke-XamlModuleBuild $staticProvider 'StaticControlsModuleLib.NoTypeInfo' @('/p:XamlCodeGenerationControlFlags=NoTypeInfoCodeGen')

$staticProviderObjRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\src\XamlCompiler\Tests\RegressionProjects\Features\StaticLibs\StaticControlsModuleLib'
$providerPrimaryHeaders = @(Get-ChildItem -Path $staticProviderObjRoot -Filter 'XamlBindingInfo.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($providerPrimaryHeaders.Count -eq 0) {
    throw 'StaticControlsModuleLib did not generate XamlBindingInfo.xaml.g.h.'
}
foreach ($header in $providerPrimaryHeaders) {
    if (Select-String -Path $header.FullName -SimpleMatch 'export import :XamlTypeInfo;' -Quiet) {
        throw "NoTypeInfoCodeGen left a stale :XamlTypeInfo export in $($header.FullName)."
    }
}

$inactiveConsumerXamlModuleDir = Join-Path $repoRoot 'BuildOutput\obj\XamlModuleValidation\InactiveConsumerXamlModules'
New-Item -ItemType Directory -Force -Path $inactiveConsumerXamlModuleDir | Out-Null
Set-Content -Path (Join-Path $inactiveConsumerXamlModuleDir 'stale.ifc') -Value 'stale'
$inactiveConsumerXamlModuleProperty = "/p:XamlCppWinRTModuleIfcDir=$inactiveConsumerXamlModuleDir\"

Invoke-XamlModuleBuild $staticConsumer 'StaticControlsModuleConsumer.CrossProject' @($inactiveConsumerXamlModuleProperty)
if (Test-Path $inactiveConsumerXamlModuleDir) {
    throw 'A module-mode C++/WinRT project with no XAML left stale XamlModules output behind.'
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
