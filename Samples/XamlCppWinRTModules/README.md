# XamlC + C++/WinRT named modules sample

This repo-local sample demonstrates the normal application shape for XamlC's C++/WinRT
3.x named-module support.

For the architecture and migration details, see
[`docs/design-notes/xamlc-cppwinrt-named-modules.md`](../../docs/design-notes/xamlc-cppwinrt-named-modules.md).

> This sample targets the implementation on `feat/xamlccppmodule/phase1`. Until that
> compiler work ships in a Windows App SDK release, build it against this repository.

## What the sample demonstrates

- `CppWinRTBuildModule=true`.
- C++/WinRT 3.x.
- `/std:c++latest` and STL modules.
- No WinRT projection headers in a PCH.
- A normal XAML class that relies on the generated
  `.g.h -> .xaml.g.h -> Application_Xaml` bridge.
- x:Bind to a runtime class in the separate
  `XamlCppWinRTModulesSample.Models` projection namespace.
- A separate source file that explicitly imports the public project XAML module.

The public XAML module is:

```cpp
import XamlCppWinRTModulesSample.Application_Xaml;
```

Normal `App.xaml.cpp` and `MainWindow.xaml.cpp` do **not** write that import.

## Build

From an initialized repository developer prompt:

```bat
init.cmd
nuget install Samples\XamlCppWinRTModules\packages.config -OutputDirectory packages -NonInteractive

msbuild Samples\XamlCppWinRTModules\XamlCppWinRTModules.vcxproj ^
  /p:Configuration=Debug ^
  /p:Platform=x64 ^
  /p:VisualStudioVersion=17.0
```

`UseXamlCompiler=true` in the project makes the sample use the compiler built from this
repository. That property is only needed for repo development; a future SDK containing
this feature supplies its own XamlC.

## Important project settings

```xml
<PropertyGroup>
  <CppWinRTBuildModule>true</CppWinRTBuildModule>
  <CppWinRTVersion>3.0.260818.1</CppWinRTVersion>
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
        |                    partition of XamlCppWinRTModulesSample.Application_Xaml
        |
        +-- XamlC shared Pass1 -> XamlBindingInfo.xaml.g.h
        |                         primary Application_Xaml interface
        |
        +-- MSVC -> $(IntDir)XamlModules\*.ifc
        |
        +-- XamlC Pass2 -> *.xaml.g.hpp / metadata-provider implementation
```

At compile time, `MainWindow.g.h` detects `MainWindow.xaml.g.h`; the XAML companion
imports the project umbrella. This is the key hand-off between C++/WinRT component
generation and XamlC module generation.

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
#define WINRT_IMPORT_MODULE
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
MainWindow namespace. XamlC records that semantic WinRT namespace and emits the required
projection dependency in the MainWindow partition.

The point is that application code does not maintain an extra list of
`import winrt....;` statements for types discovered by XAML/x:Bind.

## What to inspect after a build

The exact intermediate root is controlled by repository MSBuild properties, but the
important generated artifacts are:

```text
$(GeneratedFilesDir)XamlBindingInfo.xaml.g.h
$(GeneratedFilesDir)App.xaml.g.h
$(GeneratedFilesDir)MainWindow.xaml.g.h
$(GeneratedFilesDir)XamlTypeInfo.xaml.g.h   (when TypeInfo is generated)

$(IntDir)XamlModules\*.ifc
```

`XamlBindingInfo.xaml.g.h` is the primary
`XamlCppWinRTModulesSample.Application_Xaml` interface. App/MainWindow are partitions.

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
