# XamlCompiler validation expansion

## Checkpoint and branch scope

Phase 1 remains on `feat/xamlccppmodule/phase1`. Phase 2 starts from
`5af2c5b9b70d02f1d64aa99d01cd83e8413d5715` on
`feat/xamlccppmodule/phase2`, with a stacked PR targeting phase 1. The
phase-1 product PR is not merged or retargeted while its checks are unresolved.
This keeps validation infrastructure changes separate from the generated module
contract and allows both branches to run Actions independently.

The upstream product fix associated with #11835 is already inherited. No
additional merge is required to begin unit validation. The issue remains open;
its product-only fix must not be interpreted as a passing full test suite.

## First observed compiler failure

[PR Build 36685051922](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/36685051922),
head `f3f1cd3476cf13d029119f6f32bc59c5ce114fe0`, completed all six product
builds. Its named-module job passed `CleanModule`, `NoChangeModule` and
`OnePageChanged`, then failed `PageRemoved` with:

```text
XamlTypeInfo.g.cpp(37,10): error C1083:
Cannot open include file: 'EmptyPage.xaml.g.hpp': No such file or directory
```

`EmptyPage.xaml` remains on disk, and its authored runtime class deliberately
continues compiling after the `Page` item is removed. This is a valid fixture
transition. `CleanUpSavedState()` removed the generated companion header, but
`CompileXamlInternal.GetClassToHeaderFileMap()` reconstructed an entry from
`EmptyPage.h`'s surviving `DependentUpon` metadata and the disk file.
`TypeInfoDefinition.AllLocalHppGeneratedFiles` then supplied that entry to
`CppWinRT_TypeInfoPass2.tt`, producing the invalid include.

Commit `5af2c5b` restricts the map to canonical paths in
`SourceFileManager.ProjectXamlTaskItems`, which contains current
`ApplicationDefinition` and `Page` inputs. The existing `PageRemoved` and
`PageAddedBack` builds validate removal and restoration without cleaning.
This fixes input membership; it does not change runtime-class-to-physical-header
naming, the separate subject of upstream #11525.

## Evidence required for broad validation

| Check | Current coverage or evidence | Next acceptance evidence |
| --- | --- | --- |
| Product matrix | Six builds succeeded for the recorded failing run. | Same-HEAD build results for each new validation commit. |
| Named-module integration | Initial compilation, linking and payload construction passed; removal exposed a generator bug. | All incremental transitions, static-library consumer graph and filtered module unit tests complete. |
| Unit suite | 327 source methods, 49 existing ignores; 278 non-ignored source methods before runtime discovery. | Unfiltered discovery and TRX with executed, failed and skipped counts; zero executed tests is a failure. |
| Test prerequisites | Three managed fixture projects lack their UWP C# targets import; the legacy runner temporarily patches them and permits some failed staging/build steps. | Projects import their targets directly; the new runner builds dependencies in order and fails on missing files or failed commands. |
| Generated-code comparisons | All 44 comparison methods are ignored in the current source. | Explicit fixture builds, reviewed output differences and an intentional restoration of comparison execution. |
| Legacy native/managed fixtures | 72 solution build projects span multiple platforms and languages. | A recorded selected-project matrix, toolchain requirements and separate infrastructure/compiler failure classification. |
| Package consumers | Source-tree fixtures bypass NuGet packaging. | Build real package consumers against the produced packages. |

The source inventory is not an executed-test count. Existing ignores are not
new exclusions introduced by phase 2. No full-suite pass is claimed until the
Windows job produces results. The first run can expose additional stale test
assumptions or prerequisites; preserve those failures and diagnose them from
the first actionable error.

## Implementation boundaries

The unit job uses VS2022/MSBuild17 and restores product artifacts from the same
workflow. It builds the managed fixture assemblies, proxies and test assembly
without rebuilding their product project references. Staging overwrites copies
with current outputs and checks required files. VSTest writes a discovery list,
an execution log and TRX; artifacts upload even when validation fails.

The .NET Framework test assembly loads its UWP fixture assemblies through the
compiler metadata reader; their ProjectReferences are content/build dependencies,
not CLR assembly references. This avoids a false cross-framework restore contract
while retaining the real UWP projections used by schema and binding tests.

The focused VS2026 job retains its module filter and reuses the same unit-test
runner after its native integration tests. Neither job introduces a global
projection preamble, PCH, generated dependency exceptions, or module ownership
changes. Upstream C++/WinRT provider behavior remains a separate layer.


## Subsequent CI failures

[Phase-1 run 36695814818](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/36695814818)
passed all six product builds, Page removal/restoration and code-generation flag
transitions. `5af2c5b` therefore cleared the recorded PageRemoved failure.
The next failure was `HeaderSwitch`: the component-generated `module.g.cpp`
still imported `winrt_base` after CppWinRTBuildModule switched to false.
Phase-2 run 36697475726 failed at the same transition.

The installed CppWinRTPlus targets do not include command-line module-mode
changes in projection dependency caches. The regression-only
`CppWinRTProjectionValidation.targets` supplies a mode stamp through the
provider's existing `CustomAdditional*WinMDInputs` extension points for platform,
reference and component projection. WriteOnlyWhenDifferent preserves no-change
incrementality. This provider defect is tracked in
[#35](https://github.com/hoshiizumiya/microsoft-ui-xaml/issues/35); XamlC does not
own or regenerate the projection modules.

The phase-2 unit job failed before compiling its first dependency with MSB1006,
`Switch: win10-x64`. The runner passed a raw semicolon-delimited property value,
which MSBuild parsed as multiple property assignments. Both validation entry
points now escape the separators as `%3B`. A PowerShell-to-MSBuild 17.14 test
reproduced the original error and verified that the corrected argument yields
exactly `win;win10-x64;win10-x86;win10-arm64`.

A separate MSBuild execution test verified the imported mode target over
true → unchanged true → false → unchanged false → true. All three projection
targets reran on mode transitions and skipped unchanged builds. These checks
validate argument parsing and incremental target behavior; complete Windows
fixture compilation and unit-suite results remain pending new CI.

Runs 36707890398 (phase 1) and 36709024101 (phase 2) passed the product
matrix and all SimpleModules transitions, including HeaderSwitch and
ModuleSwitchBack. Both module jobs then failed in StaticControlsModuleLib:
CL could not open the AppointmentsProvider projection interface at a
260-character absolute path. ConsumeBinaries shortened IntDir but omitted
GeneratedFilesDir. Applying the same shortening to generated output reduces
that path to 232 characters; the path-limit diagnosis still needs a Windows
rerun to confirm.

The phase-2 unit build reached CppWinRTModuleTests but failed with CS1501.
The tests used GetNamespaces(Type, string), which existed in the compiler
but was missing from CppWinRTProjectionDependency_P.cs. The proxy now forwards
the two-argument overload through reflection. No test assertions were removed.
These fixes have not yet passed Windows CI.

The subsequent Windows logs confirm the static provider's normal full build now
passes. Its NoTypeInfoCodeGen full build then compiled the prior
XamlTypeInfo.Impl.g.cpp after the umbrella stopped exporting :XamlTypeInfo, causing
C2065 for XamlTypeInfoProvider. The gate now checks this suppression contract in
MarkupCompilePass1, restores normal TypeInfo generation, and rebuilds the provider
before testing native cross-project consumption.

The full unit assembly compiled successfully, then MSB3030 stopped its content
copy: the GenXbf ProjectReference reported an obj-path DLL absent from the restored
product artifacts. That reference remains a build dependency but no longer exports
Content for copying. CopyPrebuiltArtifacts and the runner use the product's
BuildOutput/bin/GenXBF/x64/GenXbf.dll instead; the runner still requires it to exist.
The new changes have not yet passed Windows CI.

Runs 36736919593 and 36736972563 passed the product matrix and the static
provider's TypeInfo suppression/restoration stages. Cross-project consumption then
failed with C7684: winrt_numerics resolved to IFCs in both the consumer and provider.
The pure consumer has no IDL or XAML of its own, so it now disables projection
module production and imports the static provider through the native module graph.
The gate rejects every unexpected consumer .ixx, including base/numerics, and checks
no-XAML producer-mode cleanup separately before the full consumer build.

The full unit job built its assemblies but stopped during staging because
Win8Xaml.CompilerProxies.dll was missing. Directory.Build.props defaults library
ProjectReferences to Private=false. The test project's proxy reference now sets
Private=true so the existing output staging receives its runtime dependency.
Windows results for these changes remain pending.


Runs 36751734821 and 36751811896 passed all native module stages, including
static-library cross-project consumption with no consumer-generated `.ixx`.
The remaining focused failures are two schema-loading tests looking for the
hardcoded 22621 SDK; 8 of the 10 module methods passed. The shared runner now
passes its explicit SDK selection to TestHelper for contract-file lookup and
restores the previous environment afterward. Test minimum-platform values are
unchanged.

The unfiltered TRX from 36751811896 reports total=327, executed=278, passed=25,
failed=253. The first exception is a missing Unsafe 4.0.4.1 assembly request
from System.Memory; subsequent failures repeatedly report the same initialized
metadata-reader failure. The product's packaged net472 tools contain Unsafe 6.0
and its binding redirect. Test CopyPrebuiltArtifacts now copies that same-run
System.* / Bcl runtime closure and names the packaged compiler configuration
UnitTests.dll.config, so VSTest can apply the redirects to the test assembly.
The runner requires both the Unsafe DLL and test configuration during staging.
No existing ignores or assertions were removed. Windows execution of the
runtime/configuration and schema lookup fixes is pending the next CI runs.
