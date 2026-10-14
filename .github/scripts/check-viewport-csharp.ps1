$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$out = Join-Path $repo 'artifacts/viewport'
$probe = [IO.Path]::GetFullPath("$out/probe/ViewportProbe.winmd")
# Build outside the source tree to avoid inheriting product build targets.
$project = Join-Path $env:RUNNER_TEMP 'viewport-csharp'
New-Item -ItemType Directory -Force $project | Out-Null
[xml]$packages = Get-Content "$repo/packages.config"
$version = ($packages.packages.package | Where-Object id -eq 'Microsoft.Windows.CsWinRT').version
if (-not $version) { throw 'Repository CsWinRT package version not found' }
@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <CsWinRTIncludes>ViewportProbe</CsWinRTIncludes>
    <CsWinRTInputs>$probe</CsWinRTInputs>
    <CsWinRTWindowsMetadata>sdk</CsWinRTWindowsMetadata>
    <CsWinRTGeneratedFilesDir>$out/csharp-generated</CsWinRTGeneratedFilesDir>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Windows.CsWinRT" Version="$version" />
  </ItemGroup>
</Project>
"@ | Set-Content "$project/ViewportConsumer.csproj"
@'
public static class ViewportConsumer
{
    public static void Call(ViewportProbe.FrameworkElement element)
    {
        element.InvalidateViewport();
    }
}
'@ | Set-Content "$project/ViewportConsumer.cs"
@'
<configuration>
  <packageSources><clear /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources>
</configuration>
'@ | Set-Content "$project/NuGet.Config"
Push-Location $project
& dotnet build ViewportConsumer.csproj --configuration Release --nologo 2>&1 | Tee-Object "$out/csharp.log"
$buildExit = $LASTEXITCODE
Pop-Location
if ($buildExit) { throw 'C#/WinRT projection or public instance call failed; see csharp.log' }
"C#/WinRT $version projection and public instance call passed." | Set-Content "$out/csharp-result.txt"
