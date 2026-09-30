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

$cppWinRTPackagesConfig = Join-Path $repoRoot 'src\XamlCompiler\Tests\RegressionProjects\Basic\CppWinRT\SimpleModules\packages.config'
[xml]$packagesConfig = Get-Content $cppWinRTPackagesConfig
$cppWinRTPackage = $packagesConfig.packages.package | Where-Object { $_.id -eq 'YexuanXiao.CppWinRTPlus' }
if (-not $cppWinRTPackage) {
    throw 'YexuanXiao.CppWinRTPlus was not found in the SimpleModules packages.config.'
}

Write-Host "C++/WinRT projection package: $($cppWinRTPackage.id) $($cppWinRTPackage.version)"

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
        "/p:VisualStudioVersion=$ModuleVisualStudioVersion",
        "/p:PlatformToolset=$ModulePlatformToolset",
        "/p:WindowsSdkTargetPlatformVersion=$ModuleWindowsSdkVersion",
        "/p:TargetPlatformVersion=$ModuleWindowsSdkVersion",
        "/p:WindowsTargetPlatformVersion=$ModuleWindowsSdkVersion",
        '/p:UseXamlCompiler=true',
        '/p:SkipXamlCompilerProjectReferences=true',
        '/p:IncludeXamlDlls=true',
        # UWP fixtures have no Spectre-mitigated runtime libraries.
        '/p:SpectreMitigation=false',
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

$simpleGeneratedRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Basic\CppWinRT\SimpleModules'
# ConsumeBinaries keeps generated code and XAML IFCs under the shortened test root.
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

# Validate the NoTypeInfoCodeGen Pass1 surface before restoring the provider for compilation.
# Its C++/WinRT component still requires the generated metadata-provider implementation.
Invoke-XamlModuleBuild $staticProvider 'StaticControlsModuleLib.Module'
Invoke-XamlModuleBuild -RelativeProject $staticProvider -LogName 'StaticControlsModuleLib.NoTypeInfoPass1' -Target 'MarkupCompilePass1' -ExtraProperties @('/p:XamlCodeGenerationControlFlags=NoTypeInfoCodeGen')

$staticProviderObjRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Features\StaticLibs\StaticControlsModuleLib'
$providerPrimaryHeaders = @(Get-ChildItem -Path $staticProviderObjRoot -Filter 'XamlBindingInfo.xaml.g.h' -File -Recurse -ErrorAction SilentlyContinue)
if ($providerPrimaryHeaders.Count -eq 0) {
    throw 'StaticControlsModuleLib did not generate XamlBindingInfo.xaml.g.h.'
}
foreach ($header in $providerPrimaryHeaders) {
    if (Select-String -Path $header.FullName -SimpleMatch 'export import :XamlTypeInfo;' -Quiet) {
        throw "NoTypeInfoCodeGen left a stale :XamlTypeInfo export in $($header.FullName)."
    }
}

Invoke-XamlModuleBuild $staticProvider 'StaticControlsModuleLib.TypeInfoRestored'
foreach ($header in $providerPrimaryHeaders) {
    if (-not (Select-String -Path $header.FullName -SimpleMatch 'export import :XamlTypeInfo;' -Quiet)) {
        throw "Restoring TypeInfo code generation did not restore :XamlTypeInfo in $($header.FullName)."
    }
}

# Seed the consumer's real default XAML-module output directory. Do not override
# XamlCppWinRTModuleIfcDir as a global property here: global MSBuild properties flow to
# ProjectReferences and would redirect the static provider's real Application_Xaml IFCs
# into the consumer's sentinel directory as well.
$inactiveConsumerXamlModuleDir = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Features\StaticLibs\StaticControlsModuleConsumer\StaticControlsModuleConsumer\XamlModules'
New-Item -ItemType Directory -Force -Path $inactiveConsumerXamlModuleDir | Out-Null
Set-Content -Path (Join-Path $inactiveConsumerXamlModuleDir 'stale.ifc') -Value 'stale'

# Keep the no-XAML cleanup check in producer mode; the full consumer build creates no modules.
Invoke-XamlModuleBuild -RelativeProject $staticConsumer -LogName 'StaticControlsModuleConsumer.NoXamlCleanup' -Target 'XamlCppWinRTRemoveInactiveModuleOutputs' -ExtraProperties @('/p:CppWinRTBuildModule=true')

if (Test-Path $inactiveConsumerXamlModuleDir) {
    throw 'A module-mode C++/WinRT project with no XAML left stale XamlModules output behind.'
}

Invoke-XamlModuleBuild $staticConsumer 'StaticControlsModuleConsumer.CrossProject'

$staticConsumerGeneratedRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Features\StaticLibs\StaticControlsModuleConsumer'
if (-not (Test-Path $staticConsumerGeneratedRoot)) {
    throw "Static consumer generated-files root was not created: $staticConsumerGeneratedRoot"
}
$duplicateConsumerModules = @(Get-ChildItem -Path $staticConsumerGeneratedRoot -Filter '*.ixx' -File -Recurse -ErrorAction SilentlyContinue)
if ($duplicateConsumerModules.Count -ne 0) {
    throw "Pure static consumer generated unexpected module interfaces: $($duplicateConsumerModules.FullName -join '; ')"
}

$unitTestProject = Join-Path $repoRoot 'src\XamlCompiler\Tests\UnitTests\XamlCompilerUnitTests.csproj'
& msbuild.exe $unitTestProject /t:Build /restore /p:Configuration=Debug /p:Platform=x64 "/p:VisualStudioVersion=$ModuleVisualStudioVersion" "/p:WindowsSdkTargetPlatformVersion=$ModuleWindowsSdkVersion" '/p:RuntimeIdentifiers=win%3Bwin10-x64%3Bwin10-x86%3Bwin10-arm64' /p:DisableWarnForInvalidRestoreProjects=true /m:2 /ds:false "/binaryLogger:$binlogDir\XamlCompilerUnitTests.ModuleValidation.binlog"
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
