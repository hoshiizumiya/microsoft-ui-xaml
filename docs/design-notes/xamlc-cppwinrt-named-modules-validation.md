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
