# XamlC complete upstream submission and validation

The complete upstream submission source is fork [PR #44](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/44), branch `feat/xamlccppmodule/final-from-validation`. It derives from the final [PR #40](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/40) validation source and merges upstream `main` at `25d46416b3f3c7f15dfcfe2f20b6fad4ee638e32`.

The earlier split review PRs are superseded. Compiler input/state changes, named-module generation, native build integration, succinct-collection fixes, all unit/native/package tests, generated expectations, manual validation runners, the developer sample, documentation and initialization fixes travel together.

Only fork Actions orchestration is excluded: `pr-build.yml` and `build-pr.ps1` match upstream, and the two fork module/consumer workflows are absent. The six manual validation helpers remain available.

## Architecture and baseline reconciliation

Each active XAML class owns an independent declaration module. `Application_Xaml.g.ixx` is a pure re-export aggregator. BindingInfo and TypeInfo have separate interfaces. Generated implementations remain ordinary `.cpp` translation units, with textual system/STL headers before imports and no `import std`. C++/WinRT owns the projection modules and producer scaffolding. T4 templates remain paired with their checked-in generated companions.

Upstream compiler changes and tests are retained. In particular, the ControlTemplate/x:Load inputs and binding-listener expectations are carried into both checked and free expectation paths. The checked C++ expectations retain this feature's `std::int32_t` and `std::int64_t` spelling.

The checked/free master layout is preserved rather than consolidated into `common`. The native and package fixture directories contain 79 files, all unchanged from the original PR #44 checkpoint. Additional upstream tests remain present.

## Verified pre-merge evidence

[PR Build 38584447573](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/38584447573) completed successfully on `a4d9a8b494f5dc41b1d4de44f5197c6fa58d9f27`. All 13 jobs succeeded. This is PR #44's validated source before merging the newer upstream baseline.

| Gate | Verified result |
| --- | --- |
| Formal T4 synchronization | Passed |
| Product builds | All six VS2022 configurations: x86/x64/arm64, Check and Release |
| Feature full suite | TRX: 369 total, 365 executed, 365 passed, zero failed |
| Focused module tests | TRX: 23 executed, 23 passed |
| Native consumers | Named modules, header coexistence, static libraries and incremental graph stages passed |
| Package integration | Real NuGet fixture and external product sample passed |
| Historical comparison gates | Upstream and predecessor jobs passed their historical failure policy |

The feature TRX includes all three direct `SuccinctSyntax_*` methods and `ModuleGeneratedFiles_UseOneLeadingBannerAndConsistentNativeLineEndings` as passed results. The feature suite has no allowed-failure exemption. Historical suites explicitly check the four previously recorded WMC0155 failures; their job success does not mean those historical trees have zero failures.

Native consumer validation targets x64 with the module-capable Visual Studio toolset. The six product configurations do not establish x86/arm64 named-module consumer compilation. The author also reports successful local application testing.

## Validation after the merge

The merge is checked for unresolved conflicts, XML validity, source/project preservation, paired template changes and upstream workflow equality. These checks do not replace Windows builds, formal T4 regeneration or generated-code comparisons on the merged commit.

The run above must not be attributed to the merged head. Run the product gate and manual XamlC/native/package validation runners on the exact merged source before recording final acceptance. Compare the reconciled checked/free expectations against actual output; the static merge is not regeneration.

The companion-header mapping discussion and C++/WinRT provider defects retain their own scope. Fixture workarounds do not constitute fixes to the provider package.

