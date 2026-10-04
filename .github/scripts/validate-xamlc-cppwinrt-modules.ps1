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
        [string]$Target = 'Build',
        [string]$Configuration = 'Debug'
    )

    $project = Join-Path $repoRoot $RelativeProject
    $arguments = @(
        $project,
        "/t:$Target",
        "/p:Configuration=$Configuration",
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

function Get-OneGeneratedFile([string]$Directory, [string]$Name) {
    $files = @(Get-ChildItem -Path $Directory -Filter $Name -File -Recurse -ErrorAction SilentlyContinue)
    if ($files.Count -ne 1) { throw "Expected exactly one $Name under $Directory; found $($files.Count)." }
    return $files[0]
}

function Assert-XamlGraph([string]$Directory, [string]$Namespace, [string[]]$Classes) {
    $root = Get-OneGeneratedFile $Directory 'Application_Xaml.g.ixx'
    $text = Get-Content $root.FullName -Raw
    if ($text -match '#include|namespace |export import :') { throw 'The root must only aggregate independent named modules.' }
    if (-not $text.Contains("export module $Namespace.Application_Xaml;")) { throw 'Incorrect root module identity.' }
    foreach ($class in $Classes) {
        $encoded = ($class.Split('.') | ForEach-Object { 'C_' + $_ }) -join '.'
        $identity = "$Namespace.Application_Xaml.Class.$encoded"
        if (-not $text.Contains("export import $identity;")) { throw "Root is missing $identity." }
        $source = @(Get-ChildItem $Directory -Filter '*.xaml.g.ixx' -File -Recurse | Where-Object { (Get-Content $_.FullName -Raw).Contains("export module $identity;") })
        if ($source.Count -ne 1) { throw "Expected an independent interface for $identity." }
        $interface = Get-Content $source[0].FullName -Raw
        if (-not $interface.Contains('#define XAML_IMPL_MODULE') -or -not $interface.Contains('#undef XAML_IMPL_MODULE')) { throw 'Interface lacks its producer wrapper.' }
        $headerPath = $source[0].FullName -replace '\.ixx$', '.h'
        $header = Get-Content $headerPath -Raw
        if ($header -match 'export module|Application_Xaml|WINRT_XAML') { throw "Header owns a module identity: $headerPath" }
        if (-not $header.Contains('export extern "C++"')) { throw "Header lacks external C++ ownership: $headerPath" }
        Get-OneGeneratedFile $Directory "$identity.ifc" | Out-Null
    }
    if (@([regex]::Matches($text, 'export import .*\.Class\.')).Count -ne $Classes.Count) { throw 'Unexpected class exports in aggregator.' }
    Get-OneGeneratedFile $Directory "$Namespace.Application_Xaml.ifc" | Out-Null
    Get-OneGeneratedFile $Directory "$Namespace.Application_Xaml.Support.ifc" | Out-Null
}

function Assert-RemovedClass([string]$Directory, [string]$ShortName, [string]$Identity) {
    foreach ($name in @("$ShortName.xaml.g.h", "$ShortName.xaml.g.hpp", "$ShortName.xaml.g.hpp.backup", "$ShortName.xaml.g.ixx", "$Identity.ifc")) {
        if (@(Get-ChildItem $Directory -Filter $name -File -Recurse -ErrorAction SilentlyContinue).Count -ne 0) { throw "Removed class left $name." }
    }
    if ((Get-Content (Get-OneGeneratedFile $Directory 'Application_Xaml.g.ixx').FullName -Raw).Contains("export import $Identity;")) { throw 'Removed class remains in the root.' }
}

$simpleGeneratedRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Basic\CppWinRT\SimpleModules'
$fixtureRoot = Split-Path (Join-Path $repoRoot $simpleModules)
$classes = @('Simple.App', 'Simple.MainPage', 'Simple.EmptyPage', 'Simple.Views.PanelPage', 'Simple.Controls.PanelPage')
Invoke-XamlModuleBuild $simpleModules 'SimpleModules.CleanModule'
Assert-XamlGraph $simpleGeneratedRoot 'Simple' $classes
$mainInterface = Get-OneGeneratedFile $simpleGeneratedRoot 'MainPage.xaml.g.ixx'
if (-not (Get-Content $mainInterface.FullName -Raw).Contains('export import winrt.Simple;')) { throw 'Unresolved local field dependency was not exported.' }
$mainPass2 = Get-Content (Get-OneGeneratedFile $simpleGeneratedRoot 'MainPage.xaml.g.hpp').FullName -Raw
foreach ($dependency in @('import winrt.Simple.Models;', 'import winrt.Simple.Targets;')) {
    if (-not $mainPass2.Contains($dependency)) { throw "Missing x:Bind implementation dependency: $dependency" }
}
$emptySource = Get-OneGeneratedFile $simpleGeneratedRoot 'EmptyPage.xaml.g.ixx'
$emptyIfc = Get-OneGeneratedFile $simpleGeneratedRoot 'Simple.Application_Xaml.Class.C_Simple.C_EmptyPage.ifc'
$emptySourceTime = $emptySource.LastWriteTimeUtc
$emptyIfcTime = $emptyIfc.LastWriteTimeUtc
Invoke-XamlModuleBuild $simpleModules 'SimpleModules.NoChange'
if ((Get-Item $emptyIfc.FullName).LastWriteTimeUtc -ne $emptyIfcTime) { throw 'No-change build rebuilt a class IFC.' }
(Get-Item (Join-Path $fixtureRoot 'MainPage.xaml')).LastWriteTime = (Get-Date).AddSeconds(2)
Invoke-XamlModuleBuild $simpleModules 'SimpleModules.OnePageChanged'
if ((Get-Item $emptySource.FullName).LastWriteTimeUtc -ne $emptySourceTime -or (Get-Item $emptyIfc.FullName).LastWriteTimeUtc -ne $emptyIfcTime) { throw 'Changing MainPage rebuilt the sibling EmptyPage interface.' }

Invoke-XamlModuleBuild $simpleModules 'SimpleModules.PageRemoved' @('/p:IncludeIncrementalEmptyPage=false')
Assert-RemovedClass $simpleGeneratedRoot 'EmptyPage' 'Simple.Application_Xaml.Class.C_Simple.C_EmptyPage'
Assert-XamlGraph $simpleGeneratedRoot 'Simple' @($classes | Where-Object { $_ -ne 'Simple.EmptyPage' })
Invoke-XamlModuleBuild $simpleModules 'SimpleModules.PageRestored' @('/p:IncludeIncrementalEmptyPage=true')
Assert-XamlGraph $simpleGeneratedRoot 'Simple' $classes

# Rename the actual runtime class together with its XAML/IDL/component bridge.
$original = @{}
$renamed = @{}
foreach ($file in Get-ChildItem $fixtureRoot -File | Where-Object { $_.Extension -in @('.h', '.cpp', '.ixx', '.xaml', '.idl', '.vcxproj') }) {
    $original[$file.FullName] = [IO.File]::ReadAllBytes($file.FullName)
    $target = $file.FullName -replace 'EmptyPage\.(xaml|idl|h|cpp|ixx)$', 'RenamedPage.$1'
    $renamed[$file.FullName] = $target
}
try {
    foreach ($path in $original.Keys) {
        $content = [Text.Encoding]::UTF8.GetString($original[$path]).Replace('EmptyPage', 'RenamedPage')
        [IO.File]::WriteAllText($renamed[$path], $content)
        if ($renamed[$path] -ne $path) { Remove-Item $path }
    }
    Invoke-XamlModuleBuild $simpleModules 'SimpleModules.Rename'
    Assert-RemovedClass $simpleGeneratedRoot 'EmptyPage' 'Simple.Application_Xaml.Class.C_Simple.C_EmptyPage'
    Assert-XamlGraph $simpleGeneratedRoot 'Simple' @($classes | ForEach-Object { $_.Replace('EmptyPage', 'RenamedPage') })
} finally {
    foreach ($path in $original.Keys) {
        if ($renamed[$path] -ne $path -and (Test-Path $renamed[$path])) { Remove-Item $renamed[$path] }
        [IO.File]::WriteAllBytes($path, $original[$path])
    }
}
Invoke-XamlModuleBuild $simpleModules 'SimpleModules.RenameRestored'
Assert-RemovedClass $simpleGeneratedRoot 'RenamedPage' 'Simple.Application_Xaml.Class.C_Simple.C_RenamedPage'
Assert-XamlGraph $simpleGeneratedRoot 'Simple' $classes

Invoke-XamlModuleBuild -RelativeProject $simpleModules -LogName 'SimpleModules.NoPageInterfaces' -Target 'ClCompile' -ExtraProperties @('/p:XamlCodeGenerationControlFlags=NoPageCodeGen', '/p:ValidateXamlInterfacesOnly=true')
Assert-XamlGraph $simpleGeneratedRoot 'Simple' @('Simple.App')
foreach ($page in @('MainPage', 'EmptyPage', 'PanelPage')) {
    if (@(Get-ChildItem $simpleGeneratedRoot -Filter "$page.xaml.g.h" -File -Recurse).Count -ne 0) { throw 'NoPageCodeGen retained a non-App header.' }
}
Invoke-XamlModuleBuild $simpleModules 'SimpleModules.PageCodeGenRestored'
Assert-XamlGraph $simpleGeneratedRoot 'Simple' $classes

Invoke-XamlModuleBuild $simpleModules 'SimpleModules.HeaderSwitch' @('/p:CppWinRTBuildModule=false')
if (@(Get-ChildItem $simpleGeneratedRoot -File -Recurse | Where-Object { $_.Name -like '*.g.ixx' -or ($_.Extension -eq '.ifc' -and $_.DirectoryName -like '*\XamlModules*') }).Count -ne 0) { throw 'Header mode retained XAML interfaces or IFCs.' }
Invoke-XamlModuleBuild $simpleModules 'SimpleModules.ModuleSwitchBack' @('/p:CppWinRTBuildModule=true')
Assert-XamlGraph $simpleGeneratedRoot 'Simple' $classes

$providerRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Features\StaticLibs\StaticControlsModuleLib'
Invoke-XamlModuleBuild $staticProvider 'StaticProvider.Module'
Assert-XamlGraph $providerRoot 'StaticControlsModuleLib' @('StaticControlsModuleLib.BlankUserControl')
Invoke-XamlModuleBuild -RelativeProject $staticProvider -LogName 'StaticProvider.NoTypeInfoInterfaces' -Target 'ClCompile' -ExtraProperties @('/p:XamlCodeGenerationControlFlags=NoTypeInfoCodeGen', '/p:ValidateXamlInterfacesOnly=true')
$support = Get-OneGeneratedFile $providerRoot 'XamlSupport.g.ixx'
if ((Get-Content $support.FullName -Raw).Contains('XamlTypeInfo.xaml.g.h')) { throw 'NoTypeInfoCodeGen retained TypeInfo declarations in the support module.' }
Assert-XamlGraph $providerRoot 'StaticControlsModuleLib' @('StaticControlsModuleLib.BlankUserControl')
Invoke-XamlModuleBuild $staticProvider 'StaticProvider.TypeInfoRestored'
if (-not (Get-Content $support.FullName -Raw).Contains('XamlTypeInfo.xaml.g.h')) { throw 'Restoring flags failed to restore support declarations.' }

$consumerRoot = Join-Path $repoRoot 'BuildOutput\obj\amd64chk\CompilerTests\Features\StaticLibs\StaticControlsModuleConsumer'
$sentinel = Join-Path $consumerRoot 'XamlModules'
New-Item -ItemType Directory -Force $sentinel | Out-Null
Set-Content (Join-Path $sentinel 'stale.ifc') 'stale'
Invoke-XamlModuleBuild -RelativeProject $staticConsumer -LogName 'StaticConsumer.NoXamlCleanup' -Target 'XamlCppWinRTRemoveInactiveModuleOutputs' -ExtraProperties @('/p:CppWinRTBuildModule=true')
if (Test-Path $sentinel) { throw 'No-XAML project left stale module outputs.' }
Invoke-XamlModuleBuild $staticConsumer 'StaticConsumer.CrossProject'
if (@(Get-ChildItem $consumerRoot -Filter '*.ixx' -File -Recurse).Count -ne 0) { throw 'Pure consumer generated duplicate interfaces.' }
Invoke-XamlModuleBuild $staticProvider 'StaticProvider.Header' @('/p:CppWinRTBuildModule=false')
Invoke-XamlModuleBuild $staticConsumer 'StaticConsumer.Header' @('/p:CppWinRTBuildModule=false', '/p:ValidateHeaderMode=true')
Invoke-XamlModuleBuild $staticConsumer 'StaticConsumer.ModuleRestored'

Invoke-XamlModuleBuild -RelativeProject $simpleModules -LogName 'SimpleModules.Release' -Configuration Release
Invoke-XamlModuleBuild -RelativeProject $simpleModules -LogName 'SimpleModules.ReleaseHeader' -Configuration Release -ExtraProperties @('/p:CppWinRTBuildModule=false')
Invoke-XamlModuleBuild -RelativeProject $staticProvider -LogName 'StaticProvider.ReleaseHeader' -Configuration Release -ExtraProperties @('/p:CppWinRTBuildModule=false')
Invoke-XamlModuleBuild -RelativeProject $staticConsumer -LogName 'StaticConsumer.ReleaseHeader' -Configuration Release -ExtraProperties @('/p:CppWinRTBuildModule=false', '/p:ValidateHeaderMode=true')
Invoke-XamlModuleBuild -RelativeProject $staticProvider -LogName 'StaticProvider.ReleaseModule' -Configuration Release
Invoke-XamlModuleBuild -RelativeProject $staticConsumer -LogName 'StaticConsumer.ReleaseModule' -Configuration Release

# Preserve source, scanner and IFC evidence with relative paths to avoid filename collisions.
$graphEvidence = Join-Path $binlogDir 'XamlModuleGraph'
foreach ($file in Get-ChildItem (Join-Path $repoRoot 'BuildOutput\obj') -Recurse -File | Where-Object { $_.Extension -eq '.ifc' -and $_.DirectoryName -like '*\XamlModules*' -or $_.Name -like '*.g.ixx' -or $_.Name -like '*.module.json' -or $_.Name -like '*.module.json.command' }) {
    $relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\')
    $destination = Join-Path $graphEvidence $relative
    New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
    Copy-Item $file.FullName $destination
}
& (Join-Path $PSScriptRoot 'validate-xamlc-unit-tests.ps1') -VisualStudioVersion $ModuleVisualStudioVersion -WindowsSdkVersion $ModuleWindowsSdkVersion -TestCaseFilter 'FullyQualifiedName~UnitTests.CppWinRTModuleTests' -SkipRegressionBuild
