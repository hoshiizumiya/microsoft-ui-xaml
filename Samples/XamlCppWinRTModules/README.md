# XamlC + C++/WinRT named modules sample

This repo-local sample demonstrates the normal application shape for XamlC's C++/WinRT
3.x named-module support.

For the architecture and migration details, see
[`docs/design-notes/xamlc-cppwinrt-named-modules.md`](../../docs/design-notes/xamlc-cppwinrt-named-modules.md).

> This sample targets the named-module implementation in this repository. It is a
> contributor validation sample; the feature is not yet part of a released Windows App SDK.

For implementation ownership, exact source files, MSBuild ordering, failure signatures and
acceptance criteria, see
[`xamlc-cppwinrt-named-modules-implementation-guide.md`](../../docs/design-notes/xamlc-cppwinrt-named-modules-implementation-guide.md).

The sample currently uses `YexuanXiao.CppWinRTPlus 3.1.260928.1`, based on the
C++/WinRT 3.x module implementation. Its provider-wrapper target checks whether PCH
is enabled, addressing the missing `pch.h` failure in
[fork #30](https://github.com/hoshiizumiya/microsoft-ui-xaml/issues/30).

## What the sample demonstrates

- `CppWinRTBuildModule=true`.
- C++/WinRT 3.x.
- `/std:c++latest` and STL modules.
- No WinRT projection headers in a PCH.
- A normal XAML class that relies on the generated
  `.g.h -> .xaml.g.h -> Application_Xaml` bridge.
- x:Bind to a runtime class in the separate
  `XamlCppWinRTModulesSample.Models` projection namespace.
- A separate source file that consumes the public project XAML module with a single import.

The public XAML module is:

```cpp
import XamlCppWinRTModulesSample.Application_Xaml;
```

The public consumer contract is the single import above. This sample's ordinary
`MainWindow.xaml.cpp` uses the generated component-header bridge; `XamlModuleSmoke.cpp`
also verifies direct consumption with no XamlC macros or projection preamble.

## Build

For the current C++/WinRT 3.x development branch, use a Visual Studio 2026
developer prompt. The focused repository validation uses MSVC v145 and the hosted
runner's installed Windows SDK 10.0.26100.0:

```bat
init.cmd x64chk /nopgo
nuget install Samples\XamlCppWinRTModules\packages.config -OutputDirectory packages -NonInteractive

msbuild Samples\XamlCppWinRTModules\XamlCppWinRTModules.vcxproj ^
  /p:Configuration=Debug ^
  /p:Platform=x64 ^
  /p:VisualStudioVersion=18.0 ^
  /p:PlatformToolset=v145 ^
  /p:WindowsSdkTargetPlatformVersion=10.0.26100.0 ^
  /p:TargetPlatformVersion=10.0.26100.0 ^
  /p:WindowsTargetPlatformVersion=10.0.26100.0
```

The SDK 26100 override above is a repository-validation detail for the current VS2026
hosted image. It does not change WinUI's normal product SDK package baseline.

`UseXamlCompiler=true` in the project makes the sample use the compiler built from this
repository. That property is only needed for repo development; a future SDK containing
this feature supplies its own XamlC.

## Important project settings

```xml
<PropertyGroup>
  <CppWinRTBuildModule>true</CppWinRTBuildModule>
  <CppWinRTPlusVersion>3.1.260928.1</CppWinRTPlusVersion>
  <CppWinRTEnabled>true</CppWinRTEnabled>
  <CppWinRTOptimized>true</CppWinRTOptimized>
</PropertyGroup>

<ItemDefinitionGroup>
  <ClCompile>
    <PrecompiledHeader>NotUsing</PrecompiledHeader>
    <LanguageStandard>stdcpplatest</LanguageStandard>
    <BuildStlModules>true</BuildStlModules>
  </ClCompile>
</ItemDefinitionGroup>
```

`CppWinRTBuildModule` is the feature switch. The other settings make the sample's
C++/WinRT and compiler environment unambiguous.

## What gets generated

Using `MainWindow` as the example:

```text
GreetingModel.idl / MainWindow.idl
        |
        +-- C++/WinRT -> GreetingModel.g.h, MainWindow.g.h, projection modules

MainWindow.xaml
        |
        +-- XamlC Pass1 -> MainWindow.xaml.g.h
        |                 XamlC Pass1 -> MainWindow.xaml.g.ixx
        |                    class module partition
        |
        +-- XamlC shared Pass1 -> Application_Xaml.Support.g.ixx
        |                         shared BindingInfo/TypeInfo support module
        +-- XamlC shared Pass1 -> Application_Xaml.g.ixx
        |                         public root re-exporting support and class modules
        |
        +-- MSVC -> $(IntDir)XamlModules\*.ifc
        |
        +-- XamlC Pass2 -> *.xaml.g.hpp / metadata-provider implementation
```

At compile time, `MainWindow.g.h` detects `MainWindow.xaml.g.h`; the generated XAML
companion imports the project root. This preserves the component-header path while
also allowing any consumer source to write `import XamlCppWinRTModulesSample.Application_Xaml;`.

## Normal source consumption

`MainWindow.xaml.cpp` uses platform projection modules and then includes the normal
authored component header:

```cpp
#include <windows.h>

#define WINRT_IMPORT_MODULE
import winrt.Windows.Foundation;
import winrt.Microsoft.UI.Xaml;

#include "MainWindow.xaml.h"
```

There is no explicit:

```cpp
import XamlCppWinRTModulesSample.Application_Xaml;
```

The generated C++/WinRT component header probes for
`MainWindow.xaml.g.h`. In module mode, that generated XAML companion imports the project
umbrella instead of textually redeclaring the XAML surface.

## Direct module consumption

`XamlModuleSmoke.cpp` intentionally bypasses the component-header bridge:

```cpp
import XamlCppWinRTModulesSample.Application_Xaml;

static_assert(
    sizeof(winrt::XamlCppWinRTModulesSample::implementation::XamlBindings) > 0);
```

This is useful for libraries and for validating the public module contract, but it is not
required in ordinary Page/Window implementation source.

## x:Bind and projection closure

`MainWindow.xaml` binds to:

```xml
<TextBlock Text="{x:Bind Model.Message, Mode=OneWay}" />
```

`Model` is `XamlCppWinRTModulesSample.Models.GreetingModel`, not a type in the
MainWindow namespace. XamlC records that semantic WinRT namespace while analyzing the
binding graph. A local runtimeclass can still be unresolved during Pass1 because the
intermediate component WinMD does not exist yet; Pass2 sees the completed metadata and
emits the fully resolved projection dependency directly in the generated
`MainWindow.xaml.g.hpp`.

The point is that application code does not maintain an extra list of
`import winrt....;` statements for types discovered by XAML/x:Bind.

## What to inspect after a build

The exact intermediate root is controlled by repository MSBuild properties, but the
important generated artifacts are:

```text
$(GeneratedFilesDir)Application_Xaml.Support.g.ixx
$(GeneratedFilesDir)Application_Xaml.g.ixx
$(GeneratedFilesDir)MainWindow.xaml.g.ixx
$(GeneratedFilesDir)App.xaml.g.h
$(GeneratedFilesDir)MainWindow.xaml.g.h
$(GeneratedFilesDir)XamlTypeInfo.xaml.g.h   (when TypeInfo is generated)

$(IntDir)XamlModules\*.ifc
```

`Application_Xaml.g.ixx` is the public root module interface. The support interface
is physically named `Application_Xaml.Support.g.ixx`; App and MainWindow declarations
are independent class-module interfaces. The ordinary `.g.h` and `.xaml.g.h` outputs
remain available for generated-header compatibility.

## Switching back to header mode

For comparison:

```bat
msbuild Samples\XamlCppWinRTModules\XamlCppWinRTModules.vcxproj ^
  /p:Configuration=Debug ^
  /p:Platform=x64 ^
  /p:CppWinRTBuildModule=false
```

XamlC returns to `#include <winrt/...h>` projection emission and removes the old
`$(IntDir)XamlModules\` output so stale IFCs cannot survive the mode transition.

## Migration checklist

If an existing module-enabled XAML app has an application-owned workaround:

1. Keep/enable `CppWinRTBuildModule=true`.
2. Remove the custom XAML `/FI` module preamble.
3. Remove hand-maintained generated-XAML source lists used only to inject imports.
4. Keep WinRT projection headers out of the PCH, or otherwise avoid mixing textual
   declarations with later imports.
5. Let normal component `.g.h` headers reach the XAML umbrella through their generated
   `.xaml.g.h` companion.
6. Use an explicit `import <RootNamespace>.Application_Xaml;` only when a source really
   consumes the umbrella directly.

For static libraries and incremental details, see the design document.
