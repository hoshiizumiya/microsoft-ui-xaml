# XamlC and C++/WinRT named modules

This document describes the current product design for C++/WinRT 3.x named-module XAML builds. It is a contributor contract for this branch, not a statement about a released Windows App SDK version.

## Goal

When a native XAML project enables:

```xml
<CppWinRTBuildModule>true</CppWinRTBuildModule>
```

the whole generated-code chain is module-first:

```text
IDL / WinMD
    -> C++/WinRT projection modules (`winrt.<Namespace>`)
    -> C++/WinRT producer scaffold (`<Class>.g.h`)

XAML class
    -> XamlC per-class declaration module
    -> XamlC ordinary Pass2 implementation TU

all XAML classes
    -> project `Application_Xaml` declaration aggregator

shared XAML implementation declarations
    -> BindingInfo module
    -> TypeInfo module
```

The important boundary is that XamlC modules replace XamlC textual declaration consumption. They do **not** replace C++/WinRT's own producer scaffold.

## Generated module graph

For `RootNamespace=MyApp` and XAML classes `MyApp.App`, `MyApp.MainWindow`, and `MyApp.Views.SettingsPage`, XamlC generates:

```text
MyApp.Application_Xaml                         public declaration aggregator
  export import MyApp.Application_Xaml.App
  export import MyApp.Application_Xaml.MainWindow
  export import MyApp.Application_Xaml.Views.SettingsPage

MyApp.Application_Xaml.App                     independent App declaration module
MyApp.Application_Xaml.MainWindow              independent class declaration module
MyApp.Application_Xaml.Views.SettingsPage      independent class declaration module

MyApp.Application_Xaml.BindingInfo             generated implementation-facing module
MyApp.Application_Xaml.TypeInfo                generated implementation-facing module
```

There is no `Application_Xaml.Support` module and no partition/self-import topology.

The root interface is only an aggregator:

```cpp
export module MyApp.Application_Xaml;
export import MyApp.Application_Xaml.App;
export import MyApp.Application_Xaml.MainWindow;
export import MyApp.Application_Xaml.Views.SettingsPage;
```

BindingInfo and TypeInfo are not part of the public root contract. Generated implementation translation units import them explicitly when needed.

## Per-class declaration interface

A normal runtimeclass XAML page/window produces `<Class>.xaml.g.ixx`. Conceptually:

```cpp
module;
#include <unknwn.h>
#include <winrt/base_macros.h>
#undef GetCurrentTime

export module MyApp.Application_Xaml.MainWindow;
import std;
import winrt_base;
export import winrt.Windows.Foundation;
export import winrt.Microsoft.UI.Xaml;
export import winrt.Microsoft.UI.Xaml.Markup;
export import winrt.MyApp;

#define WINRT_IMPORT_MODULE
#include "MainWindow.g.h"
#undef WINRT_IMPORT_MODULE

#define XAML_IMPL_MODULE
// XamlC MainWindowT declarations
#undef XAML_IMPL_MODULE
```

The interface has two different declaration owners:

1. `<Class>.g.h` is C++/WinRT's producer scaffold. It owns `<Class>_base`, factory scaffolding, and ABI producer details.
2. XamlC owns the XAML extension template such as `MainWindowT`.

The per-class module combines them under one BMI without making the XamlC `.xaml.g.h` a module interface.

### Projection namespace for the producer

A producer scaffold must see the projection module for the runtimeclass namespace that owns `x:Class`.

For:

```text
x:Class = MyApp.Views.SettingsPage
```

the generated class module imports:

```cpp
export import winrt.MyApp.Views;
```

It must not assume that a separate `winrt.MyApp` module exists. This matters for projects whose WinMD contains only nested namespaces.

### App is different

`App.xaml` normally has no `App.idl` and therefore no C++/WinRT `App.g.h` producer scaffold. Its XamlC module exports `AppT` directly from the XamlC App template and must not synthesize or require `App.g.h`.

## The `.xaml.g.h` file in module mode

C++/WinRT probes for `<Class>.xaml.g.h` while generating/including its normal component scaffold. XamlC therefore keeps the physical file in module mode, but it is only a declaration-free sentinel:

```cpp
#pragma once
// XamlC named-module sentinel.
// Real XAML declarations are owned by MyApp.Application_Xaml.MainWindow.
```

The sentinel does not include WinRT projection headers, does not declare `MainWindowT`, and does not contain `export module`.

In classic header mode, `.xaml.g.h` remains the normal textual declaration header.

## User-authored implementation model

C++/WinRT 3.x component implementations are ordinary C++ translation units with explicit imports. XamlC follows the same model.

A module-enabled authored XAML source looks like:

```cpp
#include <windows.h>
#define WINRT_IMPORT_MODULE

import winrt.Windows.Foundation;
import winrt.Microsoft.UI.Xaml;
import MyApp.Application_Xaml.MainWindow;

#include "MainWindow.xaml.h"
#include "MainWindow.g.cpp"
```

The authored header can continue to include the ordinary C++/WinRT producer header:

```cpp
#pragma once
#include "MainWindow.g.h"

namespace winrt::MyApp::implementation
{
    struct MainWindow : MainWindowT<MainWindow>
    {
        MainWindow();
    };
}
```

`MainWindowT` comes from the imported XamlC module. The authored code does not include `MainWindow.xaml.g.h` in module mode.

For App, a source-compatible authored header may keep a header-mode fallback:

```cpp
#pragma once
#ifndef WINRT_IMPORT_MODULE
#include "App.xaml.g.h"
#endif

namespace winrt::MyApp::implementation
{
    struct App : AppT<App>
    {
        App();
    };
}
```

The module-mode `App.cpp` imports `MyApp.Application_Xaml.App` before including this header.

## Ordinary generated implementation translation units

XamlC Pass2, BindingInfo implementation, and TypeInfo implementation are **ordinary translation units**, not named-module implementation units.

They therefore do not emit:

```cpp
module;
module MyApp.Application_Xaml;
```

and they do not import the standard-library module.

Instead the generated TU establishes textual native/STL ownership first:

```cpp
#include <windows.h>
#include <unknwn.h>
#include <algorithm>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>
// other STL headers used by generated/local code

#define WINRT_IMPORT_MODULE
import winrt_base;
import winrt.Windows.Foundation;
import winrt.Microsoft.UI.Xaml;
import MyApp.Application_Xaml.MainWindow;
```

This follows the C++/WinRT 3.x implementation pattern. It avoids the MSVC ownership conflict caused by:

```cpp
import std;
#include <list>
#include <unordered_map>
```

`WINRT_IMPORT_MODULE` allows ordinary C++/WinRT producer headers included after the imports to suppress duplicate textual WinRT projection declarations.

`import std;` remains valid in generated `.ixx` module interfaces, where the interface itself owns that module dependency and does not subsequently textually include STL headers.

## BindingInfo and TypeInfo

XamlC generates independent shared interfaces:

```text
XamlBindingInfo.xaml.g.ixx -> MyApp.Application_Xaml.BindingInfo
XamlTypeInfo.xaml.g.ixx    -> MyApp.Application_Xaml.TypeInfo
```

They are implementation-facing dependencies, not exports of `MyApp.Application_Xaml`.

TypeInfo implementation TUs explicitly import:

```cpp
import MyApp.Application_Xaml;
import MyApp.Application_Xaml.BindingInfo;
import MyApp.Application_Xaml.TypeInfo;
```

and import the semantic `winrt.*` projection dependencies discovered by XamlC.

Local authored implementation headers are included only after the generated TU has established textual STL ownership and imported the named WinRT/XamlC modules. `WINRT_IMPORT_MODULE` keeps their normal C++/WinRT header chain compatible with those imports.

## Semantic projection dependencies

XamlC tracks WinRT dependencies as namespaces, not as hard-coded header paths.

For example:

```text
Microsoft.UI.Xaml.Controls
```

is lowered to:

```cpp
#include <winrt/Microsoft.UI.Xaml.Controls.h>
```

in header mode, and:

```cpp
import winrt.Microsoft.UI.Xaml.Controls;
```

in module mode.

Dependency collection includes generated Page/App scaffolding, field types, connection-id target types, x:Bind path/value/parameter types, collection/map tracking types, member owner/type information, and unresolved local runtimeclass namespace fallbacks available during Pass1.

This is necessary because module builds cannot rely on the accidental transitive visibility that textual projection headers often provide.

## Module naming

The class module name preserves the full `x:Class` identity relative to the project root:

```text
MyApp.Views.SettingsPage
    -> MyApp.Application_Xaml.Views.SettingsPage

MyApp.Controls.SettingsPage
    -> MyApp.Application_Xaml.Controls.SettingsPage
```

Normal C++ identifier segments remain readable. Keywords and invalid segments are escaped deterministically and injectively. Unicode identifiers remain deterministic. Same-short-name classes in different namespaces therefore do not collide.

## MSBuild integration

XamlC writes the logical module name for every generated `.g.ixx` into `GeneratedModuleNames`. The MSBuild task exposes that as `XamlModuleName` metadata.

`XamlCppWinRTAddModuleInterfaces` then registers those files as:

```text
CompileAs=CompileAsCppModule
ModulesSupported=true
PrecompiledHeader=NotUsing
ModuleOutputFile=$(XamlCppWinRTModuleIfcDir)<XamlModuleName>.ifc
```

The generated interfaces include:

- every active per-class `.xaml.g.ixx`;
- `XamlBindingInfo.xaml.g.ixx`;
- optional `XamlTypeInfo.xaml.g.ixx`;
- `Application_Xaml.g.ixx`.

`AdditionalBMIDirectories` only makes existing IFC/BMI files discoverable. It does not make declarations visible and is never treated as a substitute for an explicit `import` statement.

## Incremental lifetime

`XamlModules.list` records the active logical module identities. Generated-source and IFC cleanup use the complete saved XAML project state, not only the current harvest workset.

Validation covers:

- no-change rebuild;
- one-page declaration change;
- add/remove/restore page;
- rename page;
- same-short-name classes in different namespaces;
- `NoPageCodeGen`;
- `NoTypeInfoCodeGen`;
- module -> header -> module switching;
- static-library producer/consumer graphs.

Obsolete `Application_Xaml.Support` filenames remain in cleanup lists only so builds upgraded from earlier development revisions cannot retain stale source/IFC artifacts. They are not generated or consumed by the current graph.

## Header-mode coexistence

When:

```xml
<CppWinRTBuildModule>false</CppWinRTBuildModule>
```

existing C++/WinRT XAML header generation remains active. XamlC emits normal `.xaml.g.h` / legacy Pass2 outputs and removes stale XAML module interfaces/IFCs.

The module and header modes are selected at XamlC generation time through `ProjectInfo.BuildXamlModules`. There is no `XAML_USE_MODULE` preprocessor switch controlling generated-source semantics.

## Validation layers

The PR validates the design at several levels:

1. T4 source/companion synchronization.
2. Focused generator unit tests.
3. `SimpleCppWinRTModules` real native regression build.
4. Independent static-library module producer/consumer build.
5. A real NuGet consumer built against the freshly packaged WinUI artifacts.
6. A separate product sample using C++/WinRT 3.x authored per-class imports.
7. Incremental add/remove/rename and header/module mode switching.
8. The normal six product configurations (`x86/x64/arm64`, free/chk) remain real builds and are not skipped to make module CI green.

The focused tests explicitly reject ordinary generated `.cpp` files that contain `module;` or `import std;`, reject a public Support module, and require direct per-class imports rather than relying on BMI search paths as implicit declaration visibility.

## Migration from the old `/FI` workaround

C++/WinRT 3.x documented a forced-include module preamble as a workaround for generated XAML sources that were outside its control. With XamlC itself module-aware, an application should instead:

1. enable `CppWinRTBuildModule=true`;
2. remove the XAML-only `/FI ModulePreamble.h` workaround;
3. import the generated XamlC per-class module from each authored XAML implementation TU;
4. keep `WINRT_IMPORT_MODULE` for the ordinary C++/WinRT producer-header path;
5. stop including XamlC `.xaml.g.h` from module-mode authored code;
6. import `<Root>.Application_Xaml` only when a consumer needs the whole project XAML declaration set.

The design deliberately does not introduce wrapper `.module.cpp` files or a second XamlC-specific project-reference protocol.
