# CI only: compile the same Sources.targets used by the instant compiler and run
# the repository's checked-in preprocessed T4 templates. No local codegen required.
$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$root = Join-Path $repo 'dxaml/xcp/tools/XCPTypesAutoGen'
$out = Join-Path $repo 'artifacts/viewport'
$bin = Join-Path $out 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -property installationPath
$csc = Join-Path $vs 'MSBuild/Current/Bin/Roslyn/csc.exe'
$framework = "$env:WINDIR/Microsoft.NET/Framework/v4.0.30319"

function Compile-Model([string]$folder, [string]$targets, [string]$name, [string[]]$references, [string]$kind = 'library') {
    $dir = Join-Path $root $folder
    [xml]$items = Get-Content (Join-Path $dir $targets)
    $sources = @($items.Project.ItemGroup.CompileFiles | ForEach-Object { Join-Path $dir $_.Include })
    $args = @('/nologo', '/platform:x86', "/target:$kind", '/nowarn:0067,0628,0436', "/out:$bin/$name")
    $args += @('mscorlib.dll', 'System.dll', 'System.Core.dll', 'Microsoft.CSharp.dll') | ForEach-Object { "/reference:$framework/$_" }
    $args += $references | ForEach-Object { "/reference:$bin/$_" }
    $rsp = Join-Path $bin "$name.rsp"
    ($args + $sources | ForEach-Object { '"' + $_ + '"' }) | Set-Content $rsp
    & $csc /noconfig "@$rsp"
    if ($LASTEXITCODE) { throw "Compiling $name failed: $LASTEXITCODE" }
}

Compile-Model 'OM' 'OM.Sources.targets' 'XamlGen.OM.dll' @()
Compile-Model 'XamlOM' 'XamlOM.Sources.targets' 'XamlOM.Instant.dll' @('XamlGen.OM.dll')
foreach ($module in @(@('AutoSuggestBox', 'AutoSuggestBox'), @('Controls', 'Controls'), @('ExtendedCore', 'ExCore'), @('Phone', 'Phone'))) {
    Compile-Model "Modules/$($module[0])" "XamlOM.$($module[1]).Sources.targets" "XamlOM.$($module[1]).Instant.dll" @('XamlGen.OM.dll', 'XamlOM.Instant.dll')
}
Compile-Model 'XamlGen' 'XamlGen.Sources.targets' 'XamlGen.exe' @('XamlGen.OM.dll') 'exe'
& "$bin/XamlGen.exe" -XbfGeneration full -i "$root/XamlGen" -o "$out/core" -a XamlOM.Instant.dll -a XamlOM.ExCore.Instant.dll -a XamlOM.AutoSuggestBox.Instant.dll -a XamlOM.Controls.Instant.dll
if ($LASTEXITCODE) { throw 'Core T4 generation failed' }
& "$bin/XamlGen.exe" -XbfGeneration full -i "$root/XamlGen" -o "$out/phone" -e Phone -a XamlOM.Instant.dll -a XamlOM.Phone.Instant.dll
if ($LASTEXITCODE) { throw 'Phone T4 generation failed' }

# Use the repository's own output manifest, including its class-directory copies.
[xml]$manifest = Get-Content "$root/RunCodeGen/xamlgen.runcodegen.proj"
foreach ($entry in $manifest.SelectNodes("//*[local-name()='FileInfo' and @Include]")) {
    $source = $entry.Include.Replace('$(XamlGenOutputPath)', "$out/")
    foreach ($file in Get-ChildItem $source -File) {
        $destination = Join-Path "$repo/dxaml" $entry.Destination
        New-Item -ItemType Directory -Force $destination | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
}
foreach ($entry in $manifest.SelectNodes("//*[local-name()='CreateItem' and @Include]")) {
    $source = $entry.Include.Replace('$(XamlGenOutputPath)', "$out/")
    $destination = Join-Path "$repo/dxaml" ($entry.AdditionalMetadata -replace '^Destination=', '')
    New-Item -ItemType Directory -Force $destination | Out-Null
    Copy-Item $source $destination -Force
}

$idl = Get-Content "$out/core/microsoft.ui.xaml.coretypes.idl" -Raw
$class = [regex]::Match($idl, '(?s)unsealed runtimeclass FrameworkElement\s*:.*?\n    };').Value
if (-not $class) { throw 'FrameworkElement IDL not found' }
if ($class -notmatch 'protected void InvalidateViewport\(\);' -or $class -notmatch '\[method_name\("InvalidateViewportPublic"\)\] void InvalidateViewport\(\);') {
    throw 'Expected protected and public projected names were not generated'
}
$header = Get-Content "$out/core/FrameworkClasses/FrameworkElement.g.h" -Raw
$body = Get-Content "$out/core/FrameworkClasses/FrameworkElement.g.cpp" -Raw
foreach ($interface in @('IFrameworkElement', 'IFrameworkElementProtected', 'IFrameworkElement2')) {
    if ($header -notmatch "ABI::Microsoft::UI::Xaml::$interface\b" -or $body -notmatch "__uuidof\(ABI::Microsoft::UI::Xaml::$interface\)") {
        throw "Missing interface or QI branch: $interface"
    }
}
if ($body -notmatch '->InvalidateViewportImpl\(\)' -or $body -notmatch '->InvalidateViewportPublicImpl\(\)') { throw 'Missing ABI forwarding stubs' }

# The published v1 portion must be byte-for-byte identical to main's IDL.
$baseline = git show '895a8a7c0bf4b7946d401dabddf93f8bf9d002c1:dxaml/xcp/dxaml/idl/winrt/core/microsoft.ui.xaml.coretypes.idl'
$oldClass = [regex]::Match(($baseline -join "`n"), '(?s)unsealed runtimeclass FrameworkElement\s*:.*?\n    };').Value
$v1 = ($class -split '\[contract\(Microsoft.UI.Xaml.WinUIContract, 12\)\]')[0].Trim().Replace("`r", '')
$oldV1 = ($oldClass -split '\[contract\(Microsoft.UI.Xaml.WinUIContract, 12\)\]')[0].Trim().Replace("`r", '')
if ($v1 -cne $oldV1) { throw 'Shipped FrameworkElement IDL changed' }

# Feed precisely the generated overload declaration into a minimal, independent
# MIDL runtimeclass. This isolates visibility/signature/projection constraints
# without requiring the full product's external contract dependencies.
$probe = [IO.Path]::GetFullPath((Join-Path $out 'probe'))
New-Item -ItemType Directory -Force $probe | Out-Null
$publicMethod = [regex]::Match($class, '\[method_name\("InvalidateViewportPublic"\)\] void InvalidateViewport\(\);').Value
@"
import "inspectable.idl";
namespace ViewportProbe
{
    [contractversion(12)] apicontract ProbeContract {};
    [contract(ViewportProbe.ProbeContract, 1)]
    unsealed runtimeclass FrameworkElement
    {
        [method_name("CreateInstance")] protected FrameworkElement();
        void ExistingMethod();
        protected void InvalidateViewport();
        [contract(ViewportProbe.ProbeContract, 12)]
        [interface_name("ViewportProbe.IFrameworkElement2")]
        {
            $publicMethod
        }
    };
}
"@ | Set-Content "$probe/ViewportProbe.idl"
$sdk = "${env:ProgramFiles(x86)}/Windows Kits/10"
$sdkVersion = (Get-ChildItem "$sdk/Include" -Directory | Where-Object Name -match '^10\.' | Sort-Object Name -Descending | Select-Object -First 1).Name
$sdkBin = "$sdk/bin/$sdkVersion/x64"
Push-Location $probe
& "$sdkBin/midl.exe" /winrt /nomidl /env x64 /I "$sdk/Include/$sdkVersion/um" /I "$sdk/Include/$sdkVersion/shared" /I "$sdk/Include/$sdkVersion/winrt" /metadata_dir "$sdk/UnionMetadata/$sdkVersion" /out $probe /winmd "$probe\ViewportProbe.winmd" ViewportProbe.idl 2>&1 | Tee-Object "$probe/midl.log"
$midlExit = $LASTEXITCODE
Pop-Location
if ($midlExit) { throw 'MIDL compilation failed; see midl.log' }
& "$sdkBin/cppwinrt.exe" -input "$probe/ViewportProbe.winmd" -reference sdk -output "$probe/include" 2>&1 | Tee-Object "$probe/cppwinrt.log"
if ($LASTEXITCODE) { throw 'C++/WinRT projection failed' }
@'
#include <winrt/ViewportProbe.h>
void public_call(winrt::ViewportProbe::FrameworkElement const& element)
{
    element.InvalidateViewport();
}
'@ | Set-Content "$probe/consumer.cpp"
& cl.exe /nologo /c /std:c++17 /EHsc "/I$probe/include" "/Fo$probe/consumer.obj" "$probe/consumer.cpp" 2>&1 | Tee-Object "$probe/consumer.log"
if ($LASTEXITCODE) { throw 'C++/WinRT public instance call failed to compile' }
@'
#using <ViewportProbe.winmd>
void public_call_cx(ViewportProbe::FrameworkElement^ element)
{
    element->InvalidateViewport();
}
'@ | Set-Content "$probe/consumer-cx.cpp"
& cl.exe /nologo /c /ZW /EHsc "/AI$probe" "/Fo$probe/consumer-cx.obj" "$probe/consumer-cx.cpp" 2>&1 | Tee-Object "$probe/consumer-cx.log"
if ($LASTEXITCODE) { throw 'C++/CX public instance call failed to compile' }
'T4 generation, shipped IDL comparison, QI checks, MIDL, C++/WinRT, and C++/CX public calls passed.' | Tee-Object "$out/result.txt"
