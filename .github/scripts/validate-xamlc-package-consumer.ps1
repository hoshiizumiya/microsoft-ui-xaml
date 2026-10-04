param([switch]$Pass1Only)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$testRoot = Join-Path $repoRoot 'PackageConsumerValidation'
Copy-Item (Join-Path $repoRoot 'src\XamlCompiler\Tests\PackageConsumers\NuGetModules') $testRoot -Recurse -Force
$project = Join-Path $testRoot 'NuGetModules.vcxproj'
$package = @(Get-ChildItem (Join-Path $repoRoot 'PackageStore') -Filter 'Microsoft.WindowsAppSDK.WinUI.*.nupkg' -File)
if ($package.Count -ne 1) { throw 'Expected exactly one current development package.' }
$version = $package[0].BaseName.Substring('Microsoft.WindowsAppSDK.WinUI.'.Length)
[xml]$xml = Get-Content $project
$ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')
$xml.SelectSingleNode('//m:PackageReference[@Include="Microsoft.WindowsAppSDK.WinUI"]', $ns).SetAttribute('Version', $version)
$xml.Save($project)
$feed = [Security.SecurityElement]::Escape((Join-Path $repoRoot 'PackageStore'))
$config = Join-Path $testRoot 'nuget.validation.config'
@"
<configuration><packageSources><clear/><add key="Product" value="$feed"/><add key="nuget.org" value="https://api.nuget.org/v3/index.json"/></packageSources><packageSourceMapping><clear/><packageSource key="Product"><package pattern="Microsoft.WindowsAppSDK.WinUI"/></packageSource><packageSource key="nuget.org"><package pattern="*"/></packageSource></packageSourceMapping></configuration>
"@ | Set-Content $config
# Independent package cache prevents the same dev version from reusing an older compiler.
$common = @('/restore', '/m:2', '/ds:false', '/p:Platform=x64', '/p:VisualStudioVersion=18.0', '/p:PlatformToolset=v145', '/p:WindowsTargetPlatformVersion=10.0.26100.0', '/p:WindowsPackageType=None', "/p:RestoreConfigFile=$config", "/p:RestorePackagesPath=$testRoot\packages", '/v:normal')
$binlog = Join-Path $repoRoot 'BuildOutput\binlogs'
foreach ($mode in @('Module', 'Header')) {
    foreach ($configuration in @('Debug', 'Release')) {
        $module = if ($mode -eq 'Module') { 'true' } else { 'false' }
        $intermediate = Join-Path $testRoot "obj\$mode\$configuration\"
        $target = if ($Pass1Only) { 'MarkupCompilePass1' } else { 'Build' }
        & msbuild.exe $project @common "/t:$target" "/p:Configuration=$configuration" "/p:CppWinRTBuildModule=$module" "/p:IntDir=$intermediate" "/p:OutDir=$testRoot\bin\$mode\$configuration\" "/binaryLogger:$binlog\NuGetConsumer.$mode.$configuration.binlog"
        if ($LASTEXITCODE -ne 0) { throw "NuGet consumer $mode $configuration failed: $LASTEXITCODE" }
        if ($mode -eq 'Module') {
            $root = @(Get-ChildItem $testRoot -Filter 'Application_Xaml.g.ixx' -Recurse -File)
            if ($root.Count -ne 1 -or -not (Get-Content $root[0].FullName -Raw).Contains('export module NuGetModules.Application_Xaml;')) { throw 'Automatic public root module missing.' }
            $support = @(Get-ChildItem $testRoot -Filter 'Application_Xaml.Support.g.ixx' -Recurse -File)
            if ($support.Count -ne 1 -or -not (Get-Content $support[0].FullName -Raw).Contains('export module NuGetModules.Application_Xaml.Support;')) { throw 'Automatic support module missing or incorrectly named.' }
            foreach ($class in @('App', 'MainPage', 'EmptyPage')) {
                if (@(Get-ChildItem $root[0].DirectoryName -Filter "$class.xaml.g.ixx" -Recurse -File).Count -ne 1) { throw "No automatic interface for $class." }
            }
            if (-not $Pass1Only -and @(Get-ChildItem $intermediate -Filter 'NuGetModules.Application_Xaml.ifc' -Recurse -File).Count -ne 1) { throw 'Root IFC was not automatically registered.' }
        }
        if ($Pass1Only) { break }
    }
}
