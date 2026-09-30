# XamlC C++/WinRT named modules: phase-1 implementation guide

> **Status**
>
> Phase 1 is in integration hardening. The architecture and generated-code contract are
> largely established, but the focused VS2026/MSVC v145 gate has not passed end to end.
> Classify each failure at its owning layer before changing generated code. The latest
> integration evidence and unverified stages are recorded in section 24.
>
> Main design note:
> [xamlc-cppwinrt-named-modules.md](xamlc-cppwinrt-named-modules.md)
>
> Tracking:
> [microsoft-ui-xaml#11524](https://github.com/microsoft/microsoft-ui-xaml/issues/11524)
>
> Separate path-mapping work:
> [microsoft-ui-xaml#11525](https://github.com/microsoft/microsoft-ui-xaml/issues/11525)

## 1. Phase-1 status

The work has moved beyond proof-of-concept code generation.

| Area | Status | Notes |
| --- | --- | --- |
| Public XAML module identity | Implemented | `<RootNamespace>.Application_Xaml` |
| App/Page/TypeInfo partitions | Implemented | Existing Pass1 `*.xaml.g.h` files are reused |
| Header/module dual mode | Implemented | Header mode remains supported |
| Semantic WinRT dependency model | Implemented | Namespace first; header/module syntax is backend lowering |
| Page/x:Bind projection closure | Implemented | Includes source, target, function, DP and connection-id types |
| TypeInfo projection closure | Implemented | Includes recursive generic arguments and generated metadata surfaces |
| App metadata-provider split | Implemented | Concrete provider dependency is delayed to Pass2 |
| Pass1 module registration | Implemented | XAML interfaces become `CompileAsCppModule` items |
| XAML IFC lifetime/cleanup | Implemented | Dedicated `$(IntDir)XamlModules\` tree |
| Static-library BMI propagation | Implemented design | Uses native VC/MSBuild module propagation |
| Incremental XAML item changes | Implemented coverage | Clean/no-change/edit/remove/restore/mode-switch paths are represented |
| Focused regression suite | Implemented | Simple app + static provider/consumer + unit tests |
| VS2026/v145 toolchain validation | In progress | Final focused gate still needs to become green |
| Windows SDK for focused gate | Scoped | VS2026 runner uses installed SDK 10.0.26100.0 only for this gate |
| Store runtime selection for focused gate | Scoped mitigation | Native invocations pass `SpectreMitigation=false`; follow-up linking remains unverified |
| Physical XAML companion path mapping | Out of scope | Tracked independently by #11525 |

The important distinction is:

> **Implemented** means the phase-1 architecture/code path exists and has targeted
> regression coverage. It does not mean the final end-to-end v145 gate has already
> accepted every generated module unit.

## 2. Mental model

There are two independent generators that must meet in one native module graph:

```text
IDL / WinMD
    |
    +-- C++/WinRT
    |      |
    |      +-- generated component headers
    |      +-- winrt.<Namespace> module interfaces
    |
XAML
    |
    +-- XamlC Pass1
    |      |
    |      +-- App/Page/TypeInfo *.xaml.g.h interface partitions
    |      +-- XamlBindingInfo.xaml.g.h primary interface
    |
    +-- MSBuild/VC module graph
    |      |
    |      +-- C++/WinRT .ixx interfaces
    |      +-- XamlC *.xaml.g.h interfaces
    |      +-- dependency scan
    |      +-- IFC generation
    |
    +-- XamlC Pass2
           |
           +-- *.xaml.g.hpp
           +-- metadata-provider/type-info implementation
           +-- ordinary C++ TUs consuming the already-built BMIs
```

XamlC must not invent a parallel projection-module system. C++/WinRT owns WinRT
projection modules; XamlC owns the project XAML umbrella and partitions.

## 3. Public contract

For a project with root namespace `MyApp`:

```text
MyApp.Application_Xaml
|
+-- :MyApp.App
+-- :MyApp.MainPage
+-- :MyApp.Pages.SettingsPage
+-- :XamlTypeInfo
```

The primary interface is:

```text
XamlBindingInfo.xaml.g.h
```

App/Page/Window/TypeInfo Pass1 files are interface partitions.

The public import is:

```cpp
import MyApp.Application_Xaml;
```

Normal XAML implementation source generally does not need to write this import directly.
The normal bridge remains:

```text
<Type>.g.h
    -> __has_include("<Type>.xaml.g.h")
        -> <Type>.xaml.g.h
            -> import MyApp.Application_Xaml
```

This preserves the existing generated-component-header contract.

## 4. Non-negotiable invariants

Do not change the architecture without a concrete compiler or ownership reason.

1. Preserve the normal header-mode code path.
2. Preserve C++/WinRT's existing `__has_include("<Type>.xaml.g.h")` bridge.
3. Do not add a second hand-authored `.ixx` generator for XAML.
4. Do not include C++/WinRT implementation `.g.h` files inside XAML module purview.
5. Do not model projection dependencies as physical `winrt/Foo.Bar.h` strings.
6. Do not make XamlC own the C++/WinRT ProjectReference/module-builder protocol.
7. Keep Pass2 implementation definitions out of named-module ownership when they are
   intentionally detached with `export extern "C++"`.
8. Keep `WINRT_IMPORT_MODULE` active after importing the XAML umbrella so later legacy
   C++/WinRT headers take the module-compatible path.
9. In a module-interface compile, `module;` must appear before `#pragma once` or any
   other non-comment/preprocessor content that violates the global-module-fragment rules.
10. T4 `.tt` files are the source of truth. Do not hand-edit their checked-in generated
    `.cs` outputs.

## 5. Implementation map

### Compiler state and orchestration

| File | Responsibility |
| --- | --- |
| `src/XamlCompiler/BuildTasks/CompileXamlInternal.cs` | Reads feature flags, drives Pass1/Pass2, generated-file reporting, saved-state cleanup and incremental invalidation |
| `src/XamlCompiler/BuildTasks/Microsoft/Xaml/XamlCompiler/XamlProjectInfo.cs` | Carries `UseCppWinRTNamedModules`, complete project XAML class list and codegen state into generators |

### Dependency modeling

| File | Responsibility |
| --- | --- |
| `src/XamlCompiler/BuildTasks/Microsoft/Xaml/XamlCompiler/CodeGenerators/CppWinRT_CodeGenerator.cs` | Defines semantic projection namespace helpers and lowers a namespace to a header include or named-module import |
| `src/XamlCompiler/BuildTasks/Microsoft/Xaml/XamlCompiler/CodeGenerators/PageDefinition.cs` | Computes Page/local-header dependencies and the Page/x:Bind projection closure |
| `src/XamlCompiler/BuildTasks/Microsoft/Xaml/XamlCompiler/CodeGenerators/TypeInfoDefinition.cs` | Computes TypeInfo projection dependencies, including recursive generic type arguments |
| `src/XamlCompiler/BuildTasks/Microsoft/Xaml/XamlCompiler/CodeGenerators/BindingInfoDefinition.cs` | Provides BindingInfo generation model/state |

### C++/WinRT T4 generation

Source-of-truth templates:

```text
src/XamlCompiler/BuildTasks/Microsoft/Xaml/XamlCompiler/CodeGenerators/CppWinRT/
    CppWinRT_AppPass1.tt
    CppWinRT_AppPass2.tt
    CppWinRT_PagePass1.tt
    CppWinRT_PagePass2.tt
    CppWinRT_BindingInfoPass1.tt
    CppWinRT_BindingInfoPass2.tt
    CppWinRT_TypeInfoPass1.tt
    CppWinRT_TypeInfoPass1Impl.tt
    CppWinRT_TypeInfoPass2.tt
    CppWinRT_XamlMetaDataProviderPass1.tt
    CppWinRT_XamlMetaDataProviderPass2.tt
```

The matching `.cs` files are generated artifacts.

### MSBuild integration

```text
src/XamlCompiler/Targets/Microsoft.UI.Xaml.Markup.Compiler.interop.targets
```

Important targets:

- `XamlCppWinRTRemoveInactiveModuleOutputs`
- `XamlCppWinRTAddModuleInterfaces`
- `XamlCppWinRTNormalizeModuleCompileItems`
- Pass2/late generated compile-item BMI propagation logic

### Regression coverage

```text
src/XamlCompiler/Tests/RegressionProjects/Basic/CppWinRT/SimpleModules/
src/XamlCompiler/Tests/RegressionProjects/Features/StaticLibs/StaticControlsModuleLib/
src/XamlCompiler/Tests/RegressionProjects/Features/StaticLibs/StaticControlsModuleConsumer/
src/XamlCompiler/Tests/UnitTests/CppWinRTModuleTests.cs
.github/scripts/validate-xamlc-cppwinrt-modules.ps1
```

## 6. Semantic projection dependency model

The compiler should reason about:

```text
Microsoft.UI.Xaml.Controls
```

not:

```text
winrt/Microsoft.UI.Xaml.Controls.h
```

The backend lowering is:

Header mode:

```cpp
#include <winrt/Microsoft.UI.Xaml.Controls.h>
```

Module mode:

```cpp
import winrt.Microsoft.UI.Xaml.Controls;
```

The current helper lives in `CppWinRTProjectionDependency`.

For a projected `Type`, `GetNamespaces(Type)`:

- unwraps arrays;
- filters projected primitive C++ types;
- yields the containing namespace;
- recursively follows generic arguments.

This recursive behavior is required for generated signatures such as generic collections
whose nested argument type lives in a different WinRT namespace.

## 7. Page/x:Bind dependency closure

Header mode can accidentally compile because one projection header includes another.
Named modules remove that accidental reachability.

`PageDefinition.NeededCppWinRTProjectionNamespaces` therefore has to contain every
namespace whose projected type the generated Page C++ can spell.

The closure currently covers:

- fixed Page scaffolding dependencies;
- connection-id element concrete types;
- generated field types;
- event handler types;
- x:Bind data-root type;
- bind-path step value types;
- observable vector/map item types;
- function owner type;
- function declared parameter type;
- function parameter value type;
- assignment/target type;
- target member/declaring type;
- dependency-property owner type.

A Pass1 bind step can still be unresolved before the component WinMD exists. Code that
queries `BindPathStep.ValueType`-derived properties must therefore remain null-safe.

The focused regression deliberately places source and target types in independent
namespaces:

```text
Simple.Models
Simple.Targets
```

and requires Pass2 `MainPage.xaml.g.hpp` to materialize both imports.

### Unresolved local fields in Pass1

For `<local:PropBag x:Name="propertyBagObject" />` with `xmlns:local="using:Simple"`,
Pass1 may have `FieldXamlType.UnderlyingType == null`, while XamlHarvester has
already preserved `FieldTypePath = "Simple"` and `FieldTypeShortName = "PropBag"`.
The generated declaration still names `winrt::Simple::PropBag`.

`PageDefinition` therefore calls
`CppWinRTProjectionDependency.GetNamespaces(fieldData.FieldXamlType?.UnderlyingType, fieldData.FieldTypePath)`.
The namespace fallback applies only when the reflection type is null. A resolved
primitive such as `int` must not acquire an unrelated namespace dependency from
the fallback string. The focused gate checks that Pass1 exports `winrt.Simple`.

## 8. Pass1 versus Pass2 ownership

### Pass1

Pass1 establishes declarations and module interfaces.

It cannot assume that every local runtimeclass is already resolvable from the component
WinMD. It should emit the interface surface that can be determined safely from Pass1
state.

### Pass2

Pass2 runs after the intermediate component metadata exists and can resolve local
runtimeclasses that were incomplete during Pass1.

Pass2 therefore materializes fully resolved projection dependencies needed by the
generated implementation.

This is particularly important for x:Bind.

## 9. App metadata-provider split

The App interface must not require the concrete generated
`XamlMetaDataProvider` implementation to be complete while the App partition itself is
being compiled.

The module path therefore keeps provider-dependent members as Pass1 declarations and
completes them in Pass2.

This includes generated operations around:

- App default construction and destruction;
- `GetXamlType`;
- `GetXmlnsDefinitions`;
- generated metadata-provider construction/access.

Declaring only the destructor out of line is insufficient. When authored `App.cpp`
constructs `AppT<App>`, an implicitly generated constructor can instantiate cleanup of
its `com_ptr<XamlMetaDataProvider>` member while the provider is still incomplete.
Pass1 therefore declares both `AppT()` and `~AppT()`; Pass2 defaults both after
including `XamlMetaDataProvider.h` and explicitly instantiates the App specialization.
The focused fixture's authored `App.cpp` exercises this boundary without importing the
provider implementation.

## 10. Page implementation bases

A Page partition must not textually pull a C++/WinRT component implementation `.g.h`
file into named-module purview.

For local composable bases, Pass1 forward-declares the required `<Type>_base` template.

Do not derive that forward declaration by requiring reflection `UnderlyingType` to
already exist. The local type may not be materialized yet in Pass1; the class name is
available from the parsed base-type name.

## 11. Dual-use Pass1 header shape

The same generated `*.xaml.g.h` participates in two modes.

Conceptually:

```cpp
#ifdef WINRT_XAML_MODULE_INTERFACE

module;
#include <unknwn.h>

export module MyApp.Application_Xaml:MyApp.MainPage;

#define WINRT_IMPORT_MODULE
import std;
export import winrt.Microsoft.UI.Xaml;

// exported declarations...

#else

#pragma once

#ifndef WINRT_IMPORT_MODULE
#define WINRT_IMPORT_MODULE
#endif

import MyApp.Application_Xaml;
#define WINRT_XAML_SKIP_BODY

#endif
```

The key detail is the location of `#pragma once`.

It belongs in the textual-header/shim branch, not before `module;`. MSVC diagnoses an
invalid global module fragment if `module;` no longer appears at the start of the module
unit.

## 12. MSBuild ordering

The relevant native build ordering is:

```text
CppWinRTResolveModuleReferences
        |
MarkupCompilePass1
        |
XamlCppWinRTAddModuleInterfaces
        |
CppWinRTAddModuleInterfaces
        |
XamlCppWinRTNormalizeModuleCompileItems
        |
FixupCLCompileOptions
        |
SetModuleDependencies / module scan
        |
ClCompile
```

### XamlCppWinRTAddModuleInterfaces

The target takes generated Pass1 `*.xaml.g.h` outputs and registers them as module
interface compile items:

```text
CompileAs=CompileAsCppModule
ModulesSupported=true
PrecompiledHeader=NotUsing
WINRT_XAML_MODULE_INTERFACE
ModuleOutputFile=$(IntDir)XamlModules\
```

### XamlCppWinRTNormalizeModuleCompileItems

XamlC and C++/WinRT register module interfaces independently. The final input consumed by
VC's `SetModuleDependencies` is the combined `@(ClCompile)` graph.

The normalization target therefore operates after C++/WinRT's module interface
registration and canonicalizes `CompileAsCppModule` items by physical `FullPath`.

Do not move this normalization back to the XamlC-only generated-file subset; the
duplicate-key failure that motivated it occurred after both module producers had
contributed items.

### Consumer macro and PCH-free fixture

`SimpleCppWinRTModules.vcxproj` uses `PrecompiledHeader=NotUsing`; it has no
`pch.h` or `pch.cpp`. This also lets C++/WinRT generate component implementation
files without a PCH include.

Its `ConfigureCppWinRTModuleConsumerCompileItems` target runs after
`XamlCppWinRTNormalizeModuleCompileItems` and before `FixupCLCompileOptions`.
In module mode it adds `WINRT_IMPORT_MODULE` only to compile items whose
`CompileAs` is not `CompileAsCppModule`. Do not define this consumer guard globally:
projection producers such as `winrt_base.ixx` and `winrt.*.ixx` must retain the
declarations they are building.

Authored dependencies remain separate from generated XAML dependencies. For example,
`MainPage.h` declares a `Simple.Models.BindModel` member, so authored sources that
include that header import `winrt.Simple.Models`. XamlC does not infer that dependency
from the authored header. Since the fixture also switches to header mode, those sources
select projection imports under `WINRT_IMPORT_MODULE` and corresponding projection
headers otherwise.

`XamlModuleSmoke.cpp` imports only `Simple.Application_Xaml`. Do not add a shared
import-everything preamble: that would hide missing dependencies of the XAML umbrella.

The component generator still produces implementation `.g.h` files. With `-name
Simple -prefix`, `Simple.Models.BindItem` uses `Models.BindItem.g.h/.g.cpp`,
`Simple.Models.BindModel` uses `Models.BindModel.g.h/.g.cpp`, and
`Simple.Targets.BindTarget` uses `Targets.BindTarget.g.h/.g.cpp`. Authored fixture
includes must match those component filenames. This naming correction does not
resolve the independent physical XAML companion-path mapping in upstream #11525.

Pass2 copies preprocessor definitions from the PCH-producing source or, for PCH-free
projects, ordinary Pass1 sources. The fallback excludes `CompileAsCppModule` items:
`WINRT_XAML_MODULE_INTERFACE` selects the producer branch of a dual-use XAML header
and must not leak into a late generated consumer. The fixture checks this boundary after
`XamlCppWinRTApplyGeneratedModuleReferences`.

### Legacy COM producer configuration

`XamlTypeInfo.xaml.g.h` declares `IXamlUserType : ::IUnknown` and uses that
interface in `winrt::implements`. The interop targets enable
`WINRT_ENABLE_LEGACY_COM` for named-module C++/WinRT builds, including compilation
of `winrt_base.ixx`. Including `<unknwn.h>` only in the later XAML TypeInfo
partition cannot retroactively enable classic COM support in the compiled base module.

## 13. XAML IFC lifetime

XAML module IFCs live under:

```text
$(IntDir)XamlModules\
```

They are deliberately separate from C++/WinRT projection IFCs.

The directory must be removed when:

- `CppWinRTBuildModule` becomes false; or
- the project no longer contains any XAML Page/ApplicationDefinition.

This avoids stale `Application_Xaml` modules surviving a mode or project-item change.

## 14. Incremental state

Named modules make stale generated state observable in ways header mode often hides.

The implementation handles these cases explicitly:

### No-change Pass1

Shared generated module headers still need to be re-reported as build outputs even when
their generator body is skipped.

### Removed Page

Removing a Page must:

- dirty the saved-state decision;
- regenerate the project-wide primary interface;
- remove the Page from the partition export list;
- delete stale Pass1/Pass2 generated class files and backups.

Physical deletion matters because C++/WinRT uses
`__has_include("<Type>.xaml.g.h")`.

### TypeInfo generation ordering

On a clean native Pass1, `GenerateTypeInfo` runs after the earlier generated-file list
update. `XamlTypeInfo.xaml.g.h` therefore has to be reported after it is materialized so
the MSBuild module-registration target sees the new `:XamlTypeInfo` partition.

### Module/header transition

The regression checks:

```text
module -> header -> module
IFCs:  >0    -> 0     -> >0
```

## 15. Static-library consumption

XamlC does not introduce a new cross-project module protocol.

For static-library ProjectReferences, VC/MSBuild already propagates public module BMIs
through its native module graph. `AllProjectBMIsArePublic` is the relevant native
behavior.

A consumer of a XAML static library therefore imports:

```cpp
import ControlsLibrary.Application_Xaml;
```

through the normal ProjectReference relationship.

C++/WinRT projection modules remain a separate concern. If a referenced static library
already provides projection IFCs, the consumer must not regenerate the same projection
modules. The focused fixture uses `CppWinRTModuleExclude` for namespace prefixes already
provided by the static provider.

Do not overload `CppWinRTConsumeModule` to mean "consume this library's XAML module".
That property belongs to C++/WinRT's module-builder/reference-projection protocol.

## 16. Toolchain used by phase-1 validation

C++/WinRT 3.x named-module validation currently requires a newer toolchain than the
WinUI product build baseline.

### Product PR build

```text
Visual Studio 2022
MSBuild 17.x
repository product SDK/package baseline
```

### Focused named-module validation

```text
Visual Studio 2026
MSBuild 18.x
MSVC v145
/std:c++latest
BuildStlModules=true
Windows SDK 10.0.26100.0 on the current hosted VS2026 image
```

The SDK 26100 override is scoped to the focused named-module gate. It is not a proposal to
move the whole WinUI repository from its current SDK package baseline.

The regression projects import `eng/consumebinaries.props`, which historically pins
`PlatformToolset=v142`. The module validation therefore passes `PlatformToolset=v145`
as a global MSBuild property so only this focused gate escapes the legacy test default.

## 17. T4 contributor workflow

When changing a C++/WinRT codegen template:

1. edit the `.tt` file;
2. do not hand-edit the generated `.cs`;
3. run the repository T4 transform, or let the PR T4 synchronization job do it;
4. inspect the generated `.cs` diff to verify the T4 transform produced exactly the
   intended output;
5. then validate the native regression project.

The PR workflow intentionally separates T4 synchronization from product compilation.

## 18. Regression topology

### SimpleCppWinRTModules

Covers:

- App + multiple Pages;
- x:Bind source namespace `Simple.Models`;
- unnamed concrete target namespace `Simple.Targets`;
- local composable base;
- TypeInfo;
- generated-header bridge;
- explicit umbrella import smoke;
- clean/no-change/edit/remove/restore;
- `NoPageCodeGen`;
- header/module switching.

Direct-import smoke code requires exported definitions to be complete after importing the
umbrella, for example `XamlBindings`, `XamlTypeInfoProvider`, and `IXamlUserType`.

### StaticControlsModuleLib

Acts as a XAML static-library module provider.

### StaticControlsModuleConsumer

Validates native static-library BMI propagation and prevents duplicate projection IFCs
from being regenerated in the consumer.

### CppWinRTModuleTests

Locks unit-level contracts such as:

- module naming;
- module-mode project state;
- semantic dependency lowering;
- generic namespace recursion;
- optional TypeInfo behavior;
- unresolved x:Bind step null-safety.

## 19. Failure signatures and what they mean

### WMC9999 during Pass1 with local runtimeclasses

Likely cause:

- code assumed reflection `UnderlyingType` was already available before the
  intermediate component WinMD existed.

Check:

- x:Bind `ValueType` dereferences;
- local base-class reflection;
- any newly added Pass1 dependency discovery.

### SetModuleDependencies / MultiToolTask duplicate dictionary key

Signature:

```text
SetModuleDependencies
System.ArgumentException: An item with the same key has already been added
Microsoft.Build.CPPTasks.MultiToolTask.Execute()
```

Do not immediately deduplicate only XamlC's `_GeneratedCodeFiles`.

The relevant boundary is the final combined `CompileAsCppModule` `ClCompile` set after
both XamlC and C++/WinRT register module interfaces.

### C7577: global module fragment can only appear at the start

Inspect generated `*.xaml.g.h`.

The module-interface preprocessing path must begin with:

```cpp
module;
```

A leading `#pragma once` in the interface branch is wrong.

### C1011: cannot locate standard module interface

Check toolchain before changing generated C++.

For this phase-1 work, `import std;` validation is expected to run with:

- VS2026 / MSVC v145;
- `/std:c++latest`;
- `BuildStlModules=true`.

A v142/14.29 compile is not a valid signal for the C++/WinRT 3.x named-module path.

### MSB8036: Windows SDK 10.0.22621.0 was not found on the VS2026 runner

The current `windows-2025-vs2026` hosted image exposes SDK 10.0.26100.0.

The focused module gate therefore overrides the installed target SDK to 26100. Do not
change the repository-wide SDK package baseline merely to satisfy this hosted-runner
capability check.

### LNK1104: cannot open msvcprtd.lib during CreateWinMD

The UWP fixtures use `VC_Target_Library_Platform=Store`. Repository
`eng/common.props` defaults `SpectreMitigation` to `Spectre`, but VC's
`Microsoft.Cpp.VCTools.Content.props` does not define Store library paths in its
Spectre branch. The evaluated MSVC runtime library path is consequently empty even
though projection and XAML module compilation can succeed.

The focused native validation passes `/p:SpectreMitigation=false` to
`Invoke-XamlModuleBuild`, including its ProjectReferences and header-mode transitions.
The VC property logic then selects the normal Store runtime paths. Successful linking
after the override remains subject to the next CI result; product builds and generated
imports are unchanged. Do not compensate with desktop runtime paths or `/NODEFAULTLIB`.

Microsoft documents that [Spectre-mitigated runtime libraries are unavailable for UWP](https://learn.microsoft.com/en-us/cpp/build/reference/qspectre?view=msvc-170).

### C2027: incomplete XamlMetaDataProvider from App.cpp

Read the instantiation stack. In run 36624346691, `com_ptr<XamlMetaDataProvider>`
destruction was instantiated by the implicit `AppT<App>` constructor, even though
the App destructor was already out of line. `CppWinRT_AppPass1.tt` now declares
`AppT()` and `~AppT()`; `CppWinRT_AppPass2.tt` defaults both after including
`XamlMetaDataProvider.h` and explicitly instantiates the App specialization.
The next full run reached `CreateWinMD`, clearing that particular first-stage error.
Adding the concrete provider header to the App partition would violate the Pass1 split.

### WINRT_XAML_MODULE_INTERFACE on a late Pass2 consumer

Check `MarkupCompilePass2` in `Microsoft.UI.Xaml.Markup.Compiler.interop.targets`.
For a PCH-free project, `_XamlPass1PreprocessorSource` must exclude
`CompileAsCppModule` items before collecting `PreprocessorDefinitions`. Otherwise
the producer marker can reach a generated ordinary `.cpp`, selecting the interface
branch of a dual-use XAML header. Commit `c44e4c3` fixes this source-selection boundary;
it was found by source audit, not attributed to a demonstrated CI compiler diagnostic.

### C1010 or missing component header in authored fixture code

`C1010` in the direct-import smoke indicated a fixture PCH requirement. The fixture
now uses `PrecompiledHeader=NotUsing` and has no PCH files. A missing
`Models.BindItem.g.h` versus `BindItem.g.h` is a component filename mismatch in
authored code. Neither signature justifies adding imports to an XAML partition.

### Missing pch.h in the generated provider wrapper

Do not infer the emitter from the `generated\` output directory. In run 36665332238,
`CppWinRTAddXamlMetaDataProviderCpp` in C++/WinRT 3.0.260818.1's
`Microsoft.Windows.CppWinRT.targets` emitted `XamlMetaDataProvider.cpp`, which then
includes `XamlMetaDataProvider.g.cpp`. The target's `_PCH` helper aggregates
`PrecompiledHeaderFile` metadata from all `ClCompile` items and constructs
`XamlMetaDataProviderPch` without checking `PrecompiledHeader=NotUsing`.

The embedded binlog source and generated-wrapper string establish this emitter.
Component projection's `-pch .` controls another generation path and does not clear
this wrapper include. XamlC's `CppWinRT_XamlMetaDataProviderPass2.tt` consumes a
separate scalar PCH input; changing only that input cannot fix this target's item
aggregation. [Fork #30](https://github.com/hoshiizumiya/microsoft-ui-xaml/issues/30)
records the package and upstream source pins, reproduction and PCH-enabled/disabled
acceptance cases. The intended upstream owner is `microsoft/cppwinrt`.

### Credential-provider release discovery fails with 403

`scripts/init/Initialize-Restore.ps1` calls `Initialize-NuGet.ps1` before dependency
restoration. The official installer previously queried
`api.github.com/repos/microsoft/artifacts-credprovider/releases/latest`; a hosted
run recorded `403 Forbidden` at that discovery step. The log does not preserve HTTP
response headers/body, so quota exhaustion is a plausible cause rather than a verified
diagnosis. [GitHub documents](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
an unauthenticated limit of 60 requests/hour per source IP.

`Initialize-NuGet.ps1` now downloads the official latest release assets directly:
NetFx48 plus the host-specific self-contained Net8 package, installed into the normal
NuGet plugin locations. It still installs the provider. `init.cmd` independently
checks the restore PowerShell exit code and stops on failure. Neither skipping the
provider nor repairing root packages inside the focused script preserves that flow.

## 20. Validation workflow caveat

A `workflow_dispatch` workflow is only directly runnable from the GitHub Actions UI
after the workflow exists on the repository's default branch. A workflow file introduced
only on a feature branch is useful for the eventual merged workflow but is not a reliable
feature-branch inner loop by itself.

Until the focused workflow exists on the default branch, use an existing PR workflow job
or a temporary default-branch-capable dispatch mechanism for repeated remote validation.

Do not encode this GitHub UI limitation into the XamlC architecture.

## 21. Phase-1 acceptance criteria

Phase 1 should be considered ready when all of the following are true:

- [x] project XAML umbrella and partitions are generated from existing Pass1 files;
- [x] header-mode generation and a module/header transition fixture are retained;
- [x] semantic projection dependencies are backend-lowered;
- [x] Page/x:Bind and TypeInfo dependency closures have targeted regressions;
- [x] App metadata-provider dependency is split correctly across Pass1/Pass2;
- [x] module interfaces are registered into the native VC module graph;
- [x] XAML IFC lifetime and incremental cleanup are explicit;
- [x] static-library cross-project design uses native BMI propagation;
- [x] T4 outputs are synchronized from templates rather than hand-edited;
- [ ] the focused VS2026/v145/SDK26100 regression chain is green end to end;
- [ ] any remaining compiler reachability/module-ownership errors from that gate are fixed
      without weakening the public contract;
- [ ] PR documentation reflects the final validated toolchain and regression state.

## 22. Explicitly out of scope

### Physical companion-header path mapping

Issue #11525 remains separate.

The umbrella module does not solve a mismatch between:

```text
cppwinrt logical companion lookup
<Type>.xaml.g.h
```

and the physical path at which XamlC emitted that file.

That needs an explicit mapping contract, not a change to `Application_Xaml` naming.

### Repository-wide SDK/toolset upgrade

Using v145/SDK26100 for C++/WinRT 3.x validation is not, by itself, a request to retarget
the entire WinUI repository.

## 23. Rule for future fixes

When a new compiler error appears:

1. identify whether it is a XamlC semantic dependency/ownership problem, a C++/WinRT
   projection problem, an authored fixture dependency/migration problem, or an
   MSBuild/restore/toolchain problem;
2. locate the smallest owning layer;
3. fix that layer only;
4. add or tighten a regression at the same boundary;
5. avoid compensating in application source or reintroducing the old forced-include
   workaround.

The objective is not merely to make the regression compile. The objective is to make
XamlC a native participant in the C++/WinRT named-module build model.

## 24. Integration evidence and open validation

This checkpoint is dated 2026-09-30 and is based on feature commit
[`f6d7989`](https://github.com/hoshiizumiya/microsoft-ui-xaml/commit/f6d7989fd921233f1d23a2214e5e8aeb6441eae4).
The integration-hardening and PR-decomposition notes were first maintained on
`docs/xamlc-cppwinrt-modules-hardening-20260930`, then synchronized back to
`feat/xamlccppmodule/phase1` with the package switch described below.
The status below is a checkpoint, not a live CI dashboard.

| Evidence | First blocking error or result | Owning layer and disposition |
| --- | --- | --- |
| [Run 36591969555 / job 109516642249](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/36591969555/job/109516642249), `508d6e4` | Credential-provider release API returned 403; the build subsequently started | Bootstrap discovery and batch exit-code propagation; direct asset downloads and fail-fast initialization are now present |
| [Run 36624346691 / job 109624041372](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/36624346691/job/109624041372), `b90deb9` | C2027 from incomplete provider cleanup during App base construction | XamlC App special-member placement; fixed in [ea9956f](https://github.com/hoshiizumiya/microsoft-ui-xaml/commit/ea9956f5028d5cf5910d53e19e591bcf1bd7bf5e), T4 synchronized by [5fdc435](https://github.com/hoshiizumiya/microsoft-ui-xaml/commit/5fdc435cb476c5e334e52ba6b04014473e3f4ecc) |
| [Run 36654268434 / job 109709975748](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/36654268434/job/109709975748), `5fdc435` | Six product builds passed; first module compile stage reached CreateWinMD, then LNK1104 for msvcprtd.lib | Store/Spectre library selection; scoped validation override in f6d7989 cleared this failure in the follow-up |
| [Run 36665332238 / job 109742675435](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/36665332238/job/109742675435), `f6d7989` | Six product builds passed; CreateWinMD succeeded; late generated compilation failed with C1083 for pch.h in XamlMetaDataProvider.cpp | C++/WinRT provider-wrapper target ignores NotUsing metadata; fork #30, no fix committed yet |

`CreateWinMD` links the first-stage objects to produce the intermediate component
metadata. XamlC Pass2 then consumes that metadata to resolve local types. Reaching
this link establishes progress through the first C++ compile stage, not successful
late generated implementation compilation.

The focused script runs its stages sequentially and throws on the first failed build.
The following work has coverage in source but remains unverified by the latest full run:

- successful late Pass2 compilation and final SimpleModules link;
- no-change/edit/remove/restore and `NoPageCodeGen` transitions;
- module to header to module compilation and IFC cleanup;
- static provider `NoTypeInfoCodeGen` and native cross-project BMI consumption;
- the final focused `CppWinRTModuleTests` invocation.

A synchronization-only workflow success is insufficient. For example, run 36654165811
produced a T4 bot commit and dispatched validation; the ensuing full run 36654268434
failed. Always follow the synchronized head into the run containing the module job.

### Independently reportable build defects

These reports have pinned upstream source and fork CI evidence. They are separate
from the named-module public contract and from upstream #11525:

| Report | Boundary |
| --- | --- |
| [Fork #4](https://github.com/hoshiizumiya/microsoft-ui-xaml/issues/4) | `init.cmd` must propagate restore-process failure before setting the success marker |
| [Fork #5](https://github.com/hoshiizumiya/microsoft-ui-xaml/issues/5) | Credential-provider installation should not require anonymous release JSON discovery |
| [Fork #6](https://github.com/hoshiizumiya/microsoft-ui-xaml/issues/6) | Store/UWP validation must select supported runtime-library paths instead of inheriting the unsupported Spectre default |

### PR extraction and separately owned provider work

The [PR decomposition index](xamlc-cppwinrt-named-modules-pr-decomposition.md)
links #4–#30 to development commits, dependencies and review boundaries. Module
hardening findings belong with their feature changes; common incremental fixes and
bootstrap fixes can be reviewed independently. Validation tasks are explicitly
identified rather than presented as demonstrated product defects.

[Provider-wrapper PCH selection (#30)](https://github.com/hoshiizumiya/microsoft-ui-xaml/issues/30)
is independently owned by C++/WinRT MSBuild. Its actual generated emitter is established
by the failure log and embedded binlog imports. It does not establish a projection
module ownership or reachability defect. The Microsoft package failure remains a
separate report; the validation projects now consume CppWinRTPlus as described below.

## 25. CppWinRTPlus integration validation

The three module regression projects and `Samples/XamlCppWinRTModules` now pin
`YexuanXiao.CppWinRTPlus 3.1.260928.1`. Package manifests, native props/targets
imports, missing-package checks and the focused restore script are switched together.
The repository-wide product C++/WinRT dependency is unchanged.

The actual NuGet archive contains `build/native/YexuanXiao.CppWinRTPlus.targets`.
Its `CppWinRTAddXamlMetaDataProviderCpp` adds this condition:

```xml
<_PCH Condition="'%(CLCompile.PrecompiledHeader)' != 'NotUsing'">@(ClCompile->Metadata('PrecompiledHeaderFile')->Distinct())</_PCH>
```

For the PCH-free SimpleModules project, the guard prevents the unused default
`PrecompiledHeaderFile` metadata from enabling an include. This is the relevant
package-level change for #30. Package inspection establishes the guard, not a
successful Windows build or every mixed-PCH/incremental edge case in that report.
The [CppWinRTPlus source](https://github.com/YexuanXiao/cppwinrtplus/blob/c14749f2f378565acfbb2633fe34d1eadfc6b2f6/nuget/YexuanXiao.CppWinRTPlus.targets)
contains the same condition.

Module target names and properties remain the existing C++/WinRT contract. The
package still registers projection producers through `CppWinRTAddModuleInterfaces`
and uses `$(IntDir)Microsoft\cppwinrt\` for projection IFCs. XamlC continues to
emit its own interfaces to `$(IntDir)XamlModules\`. No generator-specific package
branch, extra projection import or fixture PCH is introduced.

Next validation order:

1. Confirm the CI log restores the pinned Plus package and the generated provider
   wrapper no longer includes `pch.h`; then complete late Pass2 compilation and the
   SimpleModules link.
2. Run the existing no-change/edit/remove/restore, codegen-flag and module/header
   transition stages. Classify any first error by its actual emitting layer.
3. Run the static provider, `NoTypeInfoCodeGen`, native cross-project consumer and
   final unit-test stage. Do not infer BMI propagation success from the Simple build.
4. Extract independently reviewable fixes using the issue index. When the Microsoft
   package incorporates the required fixes, revalidate it explicitly before claiming
   compatibility with that upstream package.
