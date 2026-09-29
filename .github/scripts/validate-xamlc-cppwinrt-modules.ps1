param(
    [string]$ModuleVisualStudioVersion = '18.0',
    [string]$ModulePlatformToolset = 'v145',
    [string]$ModuleWindowsSdkVersion = '10.0.26100.0'
)

$ErrorActionPreference = 'Stop'

if (-not $env:VisualStudioVersion -or [version]$env:VisualStudioVersion -lt [version]'18.0') {
    throw "C++/WinRT 3.x named-module validation requires Visual Studio 2026 / MSVC v145 or later. Current VisualStudioVersion='$($env:VisualStudioVersion)'."
}

Write-Host "C++/WinRT named-module validation: VisualStudioVersion=$ModuleVisualStudioVersion PlatformToolset=$ModulePlatformToolset WindowsSdk=$ModuleWindowsSdkVersion VCToolsInstallDir=$env:VCToolsInstallDir"

$programFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
$installedSdkLib = Join-Path $programFilesX86 "Windows Kits\10\Lib\$ModuleWindowsSdkVersion"
if (-not (Test-Path $installedSdkLib)) {
    throw "Windows SDK $ModuleWindowsSdkVersion is required for named-module validation but was not found at '$installedSdkLib'."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$binlogDir = Join-Path $repoRoot 'BuildOutput\binlogs'
New-Item -ItemType Directory -Force -Path $binlogDir | Out-Null

$packagesDir = Join-Path $repoRoot 'packages'
$nugetConfig = Join-Path $repoRoot 'NuGet.config'
$nuget = Get-Command nuget.exe -ErrorAction Stop

# init.cmd normally restores these repository packages, but its credential-provider
# bootstrap can be interrupted by an external GitHub Releases API failure. The focused
# module gate must not depend on that unrelated side effect: restore the exact package
# roots consumed by these regression projects when they are absent.
$rootPackagesConfig = Join-Path $repoRoot 'packages.config'
[xml]$rootPackages = Get-Content $rootPackagesConfig
$cachePackage = $rootPackages.packages.package | Where-Object { $_.id -eq 'Microsoft.MSBuildCache.Local' }
if (-not $cachePackage) {
    throw 'Microsoft.MSBuildCache.Local was not found in packages.config.'
}

$cachePackageDir = Join-Path $packagesDir ("{0}.{1}" -f $cachePackage.id, $cachePackage.version)
if (-not (Test-Path $cachePackageDir)) {
    foreach ($config in @($rootPackagesConfig, (Join-Path $repoRoot 'packages.x64.config'))) {
        & $nuget.Source restore $config -ConfigFile $nugetConfig -PackagesDirectory $packagesDir -NonInteractive
        if ($LASTEXITCODE -ne 0) {
            throw "NuGet restore for $config failed with exit code $LASTEXITCODE."
        }
    }
}

function Get-OssPackageVersion {
    param([Parameter(Mandatory)] [string]$PropertyName)

    [xml]$versions = Get-Content (Join-Path $repoRoot 'eng\Versions.props')
    $node = @($versions.SelectNodes("//$PropertyName")) |
        Where-Object { $_.Condition -and $_.Condition -match 'IsInternalWinUIBuild' -and $_.Condition -match '!=' } |
        Select-Object -Last 1
    if (-not $node -or [string]::IsNullOrWhiteSpace($node.InnerText)) {
        throw "Could not resolve the OSS package version for $PropertyName from eng\Versions.props."
    }
    return $node.InnerText.Trim()
}

function Install-NuGetPackageIfMissing {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Version
    )

    $legacyPackageDir = Join-Path $packagesDir ("{0}.{1}" -f $Id, $Version)
    $globalPackageDir = Join-Path $packagesDir ((Join-Path $Id.ToLowerInvariant() $Version))
    if ((Test-Path $legacyPackageDir) -or (Test-Path $globalPackageDir)) {
        return
    }

    & $nuget.Source install $Id -Version $Version -OutputDirectory $packagesDir -ConfigFile $nugetConfig -NonInteractive
    if ($LASTEXITCODE -ne 0) {
        throw "NuGet install for $Id $Version failed with exit code $LASTEXITCODE."
    }
}

# These two PackageReference dependencies are normally restored by
# eng\Microsoft.MaestroRestore.csproj during full init. They are the only Maestro
# packages consumed by the focused module fixtures.
Install-NuGetPackageIfMissing 'Microsoft.Internal.WinUIDetails' (Get-OssPackageVersion 'WinUIDetailsNugetVersion')
Install-NuGetPackageIfMissing 'Microsoft.WindowsAppSDK.Foundation' (Get-OssPackageVersion 'FoundationTransportPackageVersion')

$cppWinRTPackagesConfig = Join-Path $repoRoot 'src\XamlCompiler\Tests\RegressionProjects\Basic\CppWinRT\SimpleModules\packages.config'
[xml]$packagesConfig = Get-Content $cppWinRTPackagesConfig
$cppWinRTPackage = $packagesConfig.packages.package | Where-Object { $_.id -eq 'Microsoft.Windows.CppWinRT' }
if (-not $cppWinRTPackage) {
    throw 'Microsoft.Windows.CppWinRT was not found in the SimpleModules packages.config.'
}

$cppWinRTPackageDir = Join-Path $repoRoot ("packages\{0}.{1}" -f $cppWinRTPackage.id, $cppWinRTPackage.version)
if (-not (Test-Path $cppWinRTPackageDir)) {
    & $nuget.Source install $cppWinRTPackage.id -Version $cppWinRTPackage.version -OutputDirectory $packagesDir -Source https://api.nuget.org/v3/index.json -NonInteractive
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
        "/p:VisualStudioVersion=$ModuleVisualStudioVersion",
        "/p:PlatformToolset=$ModulePlatformToolset",
        "/p:WindowsSdkTargetPlatformVersion=$ModuleWindowsSdkVersion",
        "/p:TargetPlatformVersion=$ModuleWindowsSdkVersion",
        "/p:WindowsTargetPlatformVersion=$ModuleWindowsSdkVersion",
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

$simpleGeneratedRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\src\XamlCompiler\Tests\RegressionProjects\Basic\CppWinRT\SimpleModules'
# ConsumeBinaries rewrites IntDir from ...\src\XamlCompiler\Tests\RegressionProjects\...
# to ...\CompilerTests\..., while GeneratedFilesDir retains the source-relative path.
# XAML IFCs are emitted under $(IntDir)XamlModules\, so validate them from the rewritten
# compiler-test intermediate root instead of the generated-code root.
$simpleIntRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Basic\CppWinRT\SimpleModules\SimpleCppWinRTModules'
$mainPageModuleHeaders = @(Get-ChildItem -Path $simpleGeneratedRoot -Filter 'MainPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($mainPageModuleHeaders.Count -eq 0) {
    throw 'SimpleModules did not generate MainPage.xaml.g.h.'
}
foreach ($header in $mainPageModuleHeaders) {
    if (-not (Select-String -Path $header.FullName -SimpleMatch 'export import winrt.Simple;' -Quiet)) {
        throw "MainPage Pass1 did not import the unresolved local field projection namespace: winrt.Simple"
    }
}

$mainPagePass2Files = @(Get-ChildItem -Path $simpleGeneratedRoot -Filter 'MainPage.xaml.g.hpp' -File -Recurse -ErrorAction SilentlyContinue)
if ($mainPagePass2Files.Count -eq 0) {
    throw 'SimpleModules did not generate MainPage.xaml.g.hpp.'
}
$requiredPageProjectionImports = @(
    'import winrt.Simple.Models;',
    'import winrt.Simple.Targets;'
)
foreach ($requiredImport in $requiredPageProjectionImports) {
    $found = $false
    foreach ($pass2File in $mainPagePass2Files) {
        if (Select-String -Path $pass2File.FullName -SimpleMatch $requiredImport -Quiet) {
            $found = $true
            break
        }
    }
    if (-not $found) {
        throw "MainPage Pass2 did not import required x:Bind projection dependency: $requiredImport"
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

$staleEmptyPageHeaders = @(Get-ChildItem -Path $simpleGeneratedRoot -Filter 'EmptyPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($staleEmptyPageHeaders.Count -ne 0) {
    throw "Removed XAML Page left a stale EmptyPage.xaml.g.h: $($staleEmptyPageHeaders.FullName -join '; ')"
}

Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.PageAddedBack' @('/p:IncludeIncrementalEmptyPage=true')
$restoredEmptyPageHeaders = @(Get-ChildItem -Path $simpleGeneratedRoot -Filter 'EmptyPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($restoredEmptyPageHeaders.Count -eq 0) {
    throw 'Restoring EmptyPage.xaml did not regenerate EmptyPage.xaml.g.h.'
}

# NoPageCodeGen is a Pass1 code-generation mode, so validate its module partition
# contract without compiling application sources that intentionally depend on Page
# InitializeComponent output.
Invoke-XamlModuleBuild -RelativeProject $simpleModules -LogName 'SimpleCppWinRTModules.NoPagePass1' -Target 'MarkupCompilePass1' -ExtraProperties @('/p:XamlCodeGenerationControlFlags=NoPageCodeGen')

$simplePrimaryHeaders = @(Get-ChildItem -Path $simpleGeneratedRoot -Filter 'XamlBindingInfo.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
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

$noPageAppHeaders = @(Get-ChildItem -Path $simpleGeneratedRoot -Filter 'App.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
$noPageMainPageHeaders = @(Get-ChildItem -Path $simpleGeneratedRoot -Filter 'MainPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
$noPageEmptyPageHeaders = @(Get-ChildItem -Path $simpleGeneratedRoot -Filter 'EmptyPage.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
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
    if (@(Get-ChildItem -Path $simpleGeneratedRoot -Filter $pageHeaderName -File -Recurse -ErrorAction SilentlyContinue).Count -eq 0) {
        throw "Restoring Page codegen did not regenerate $pageHeaderName."
    }
}

$moduleIfcsBeforeHeaderSwitch = @(Get-ChildItem -Path $simpleIntRoot -Filter '*.ifc' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\XamlModules*' })
if ($moduleIfcsBeforeHeaderSwitch.Count -eq 0) {
    throw 'Module-mode build did not produce any XAML IFCs before the header-mode transition.'
}

Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.HeaderSwitch' @('/p:CppWinRTBuildModule=false')
$moduleIfcsInHeaderMode = @(Get-ChildItem -Path $simpleIntRoot -Filter '*.ifc' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*\XamlModules*' })
if ($moduleIfcsInHeaderMode.Count -ne 0) {
    throw "Header-mode build left stale XAML IFCs: $($moduleIfcsInHeaderMode.FullName -join '; ')"
}

Invoke-XamlModuleBuild $simpleModules 'SimpleCppWinRTModules.ModuleSwitchBack' @('/p:CppWinRTBuildModule=true')
$moduleIfcsAfterSwitchBack = @(Get-ChildItem -Path $simpleIntRoot -Filter '*.ifc' -File -Recurse -ErrorAction SilentlyContinue |
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

# Seed the consumer's real default XAML-module output directory. Do not override
# XamlCppWinRTModuleIfcDir as a global property here: global MSBuild properties flow to
# ProjectReferences and would redirect the static provider's real Application_Xaml IFCs
# into the consumer's sentinel directory as well.
$inactiveConsumerXamlModuleDir = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Features\StaticLibs\StaticControlsModuleConsumer\StaticControlsModuleConsumer\XamlModules'
New-Item -ItemType Directory -Force -Path $inactiveConsumerXamlModuleDir | Out-Null
Set-Content -Path (Join-Path $inactiveConsumerXamlModuleDir 'stale.ifc') -Value 'stale'

Invoke-XamlModuleBuild $staticConsumer 'StaticControlsModuleConsumer.CrossProject'
if (Test-Path $inactiveConsumerXamlModuleDir) {
    throw 'A module-mode C++/WinRT project with no XAML left stale XamlModules output behind.'
}

$staticConsumerGeneratedRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\src\XamlCompiler\Tests\RegressionProjects\Features\StaticLibs\StaticControlsModuleConsumer'
if (-not (Test-Path $staticConsumerGeneratedRoot)) {
    throw "Static consumer generated-files root was not created: $staticConsumerGeneratedRoot"
}
$duplicateConsumerModules = @(Get-ChildItem -Path $staticConsumerGeneratedRoot -Filter '*.ixx' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like 'winrt.Windows.*.ixx' -or
        $_.Name -like 'winrt.Microsoft.*.ixx' -or
        $_.Name -like 'winrt.StaticControlsModuleLib*.ixx'
    })
if ($duplicateConsumerModules.Count -ne 0) {
    throw "Static consumer regenerated projection modules already supplied by its provider: $($duplicateConsumerModules.FullName -join '; ')"
}

$unitTestProject = Join-Path $repoRoot 'src\XamlCompiler\Tests\UnitTests\XamlCompilerUnitTests.csproj'
& msbuild.exe $unitTestProject /t:Build /restore /p:Configuration=Debug /p:Platform=x64 "/p:VisualStudioVersion=$ModuleVisualStudioVersion" "/p:WindowsSdkTargetPlatformVersion=$ModuleWindowsSdkVersion" '/p:RuntimeIdentifiers=win;win10-x64;win10-x86;win10-arm64' /p:DisableWarnForInvalidRestoreProjects=true /m:2 /ds:false "/binaryLogger:$binlogDir\XamlCompilerUnitTests.ModuleValidation.binlog"
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
