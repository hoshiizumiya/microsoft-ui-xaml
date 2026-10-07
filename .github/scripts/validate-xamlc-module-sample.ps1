param([string]$SampleRoot)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $SampleRoot) { $SampleRoot = Join-Path $repoRoot 'SampleValidation' }

$smoke = Get-Content (Join-Path $repoRoot 'Samples\XamlCppWinRTModules\XamlModuleSmoke.cpp') -Raw
if (-not $smoke.Contains('import XamlCppWinRTModulesSample.Application_Xaml;') -or $smoke -match 'XAML_(IMPL|USE)_MODULE') {
    throw 'Direct sample consumer is not using the plain public root import.'
}

$package = @(Get-ChildItem (Join-Path $repoRoot 'PackageStore') -Filter 'Microsoft.WindowsAppSDK.WinUI.*.nupkg' -File)
if ($package.Count -ne 1) { throw 'Expected one freshly built WinUI package.' }
$version = $package[0].BaseName.Substring('Microsoft.WindowsAppSDK.WinUI.'.Length)
$sampleCommit = '139aad9a373b183030789f97797b1838f1685afb'
git clone https://github.com/hoshiizumiya/WinUICppwinrtModuleSample.git $SampleRoot
if ($LASTEXITCODE -ne 0) { throw 'Sample clone failed.' }
git -C $SampleRoot checkout --detach $sampleCommit
if ($LASTEXITCODE -ne 0) { throw 'Sample checkout failed.' }
Write-Host "Validating product sample $sampleCommit with WinUI $version"

$project = Join-Path $SampleRoot 'WinUICppwinrtModuleSample\WinUICppwinrtModuleSample.vcxproj'
[xml]$projectXml = Get-Content $project
$manager = New-Object Xml.XmlNamespaceManager($projectXml.NameTable)
$manager.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')
$reference = $projectXml.SelectSingleNode('//m:PackageReference[@Include="Microsoft.WindowsAppSDK.WinUI"]', $manager)
$reference.SetAttribute('Version', $version)
$projectXml.Save($project)

$feed = [Security.SecurityElement]::Escape((Join-Path $repoRoot 'PackageStore'))
$config = Join-Path $SampleRoot 'nuget.validation.config'
@"
<configuration>
  <packageSources><clear/><add key="Product" value="$feed"/><add key="nuget.org" value="https://api.nuget.org/v3/index.json"/></packageSources>
  <packageSourceMapping><clear/><packageSource key="Product"><package pattern="Microsoft.WindowsAppSDK.WinUI"/></packageSource><packageSource key="nuget.org"><package pattern="*"/></packageSource></packageSourceMapping>
</configuration>
"@ | Set-Content $config

foreach ($configuration in @('Debug', 'Release')) {
    $intermediate = Join-Path $SampleRoot "obj\$configuration\"
    & msbuild.exe $project /restore /t:Build /m:2 /ds:false "/p:Configuration=$configuration" /p:Platform=x64 /p:VisualStudioVersion=18.0 /p:PlatformToolset=v145 /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:WindowsPackageType=None /p:AppxPackage=false "/p:RestoreConfigFile=$config" "/p:RestorePackagesPath=$SampleRoot\packages" "/p:IntDir=$intermediate" "/p:OutDir=$SampleRoot\bin\$configuration\" "/binaryLogger:$repoRoot\BuildOutput\binlogs\ProductSample.$configuration.binlog"
    if ($LASTEXITCODE -ne 0) { throw "Sample $configuration failed: $LASTEXITCODE" }

    $root = @(Get-ChildItem $intermediate -Filter 'Application_Xaml.g.ixx' -Recurse -File)
    if ($root.Count -ne 1) { throw 'Sample did not receive an automatic root aggregator.' }
    $rootText = Get-Content $root[0].FullName -Raw
    if (-not $rootText.Contains('export module WinUICppwinrtModuleSample.Application_Xaml;')) { throw 'Sample root module has the wrong identity.' }
    if ($rootText -match '#include|namespace |Application_Xaml\.Support') { throw 'Sample root is not a pure class-module aggregator.' }

    foreach ($obsolete in @('Application_Xaml.Support.g.ixx', 'XamlSupport.g.ixx', 'WinUICppwinrtModuleSample.Application_Xaml.Support.ifc')) {
        if (@(Get-ChildItem $intermediate -Filter $obsolete -Recurse -File -ErrorAction SilentlyContinue).Count -ne 0) {
            throw "Sample retained obsolete support artifact $obsolete."
        }
    }

    foreach ($class in @('App', 'MainWindow')) {
        $interface = @(Get-ChildItem $intermediate -Filter "$class.xaml.g.ixx" -Recurse -File)
        if ($interface.Count -ne 1) { throw "Sample lacks $class interface." }
        $identity = "WinUICppwinrtModuleSample.Application_Xaml.$class"
        $interfaceText = Get-Content $interface[0].FullName -Raw
        if (-not $interfaceText.Contains("export module $identity;")) { throw "$class interface has the wrong module identity." }
        if (-not $rootText.Contains("export import $identity;")) { throw "Root does not re-export $identity." }
        if (@(Get-ChildItem $intermediate -Filter "$identity.ifc" -Recurse -File).Count -ne 1) { throw "Sample lacks $class IFC." }
    }

    if (@(Get-ChildItem $intermediate -Filter 'WinUICppwinrtModuleSample.Application_Xaml.ifc' -Recurse -File).Count -ne 1) {
        throw 'Sample lacks the root XAML IFC.'
    }

    foreach ($generated in @(Get-ChildItem $intermediate -Filter '*.xaml.g.cpp' -Recurse -File) + @(Get-ChildItem $intermediate -Filter 'XamlTypeInfo*.g.cpp' -Recurse -File)) {
        $text = Get-Content $generated.FullName -Raw
        if ($text -match '(?m)^module;$' -or $text.Contains('import std;')) {
            throw "Sample generated ordinary TU has module/STL ownership regression: $($generated.FullName)"
        }
    }
}
