# XamlC named-module review and validation plan

## Product integration

PR [#1](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/1) is merged.
`feat/xamlccppmodule/product` contains three review commits on upstream `4f7cd8dc`:

| Commit | Scope |
| --- | --- |
| `9acf3ba` | Common incremental flags/input ownership: CompileXamlInternal.cs and SaveState.cs |
| `f048196` | Named-module compiler/targets and 10 unit methods under the current proxy layout |
| `44a3dfd` | Architecture, implementation guide and developer sample |

The product diff contains 59 files. Bootstrap changes, fork workflows, native validation
fixtures and this issue-management index are outside product. Upstream test staging,
SDK discovery, TestHelper.cs, eng/consumebinaries.props and XamlCompilerTests.sln are
retained. Upstream #11837's proxy relocation and test fixes are included; old UWP imports,
secondary UnitTestingBin staging and hand-maintained SDK fallback are not replayed.

The old development tips remain available on
`archive/xamlc-phase1-before-product-rebase-20261001` and
`archive/xamlc-phase2-before-product-rebase-20261001`.

## Review order

| Review PR | Issues | Dependency | Upstream extraction |
| --- | --- | --- | --- |
| [#37 bootstrap](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/37) | #4, #5, #7 | Independent | Two initialization files, no compiler/workflow changes |
| [#38 incremental](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/38) | #8, #9 | Independent | Two compiler files; merge before modules |
| [#39 modules](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/39) | #10–#25 | #38 | 39 files relative to review/xamlc-incremental |
| [#36 docs/sample](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/36) | #3 documentation | #39 | 19 files relative to review/xamlc-named-modules |
| Product validation successor to #33 | #6, #26–#29, #31, #32, #35 workaround | Product | Fork CI/native fixtures; not an upstream product prerequisite |

Do not submit each module-hardening issue as an independently mergeable patch.
The primary interface, partition ownership, semantic dependency closure and native
build registration must work together; separating them into unfinished intermediate
states would leave code that cannot compile. The unit regressions accompany the owning
module commit. Generated C# remains with its authoritative T4 templates.

The connected GitHub App rejected upstream PR creation with
`Resource not accessible by integration`. The fork drafts hold exact changes and prepared
technical descriptions. When upstream submission is available, submit #37/#38 first;
after #38 lands, rebase #39 onto upstream main, then submit #36 after #39. No upstream
PR number is claimed in this document.

## Issue disposition

| Reports | Final disposition |
| --- | --- |
| #2 | Superseded by #3/product tracker; original per-Page module design is obsolete |
| #3 | Product integration complete; keep open for upstream/rebased acceptance |
| #4, #5, #7 | Extracted, open until independent upstream review is resolved |
| #8, #9 | Implemented in product; independent upstream review remains open |
| #10–#25 | Feature implementation completed in product; upstream review is grouped in #39 |
| #6 | Runtime-library override is scoped to original UWP validation fixtures |
| #26–#29, #31 | Original focused integration accepted; new validation branch needs a fresh run |
| #30 | C++/WinRT provider-wrapper defect; third-party fixture mitigation is not an upstream fix |
| #35 | C++/WinRT projection incremental-input defect; fixture cache is not a package fix |
| #32 | Full suite/codegen comparison acceptance remains open |

## Verified evidence

[Run 36811821254](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/36811821254)
passed six product jobs and
[module job 110224032924](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/36811821254/job/110224032924).
The native chain includes clean/no-change/one-Page rebuild, removal/restoration,
NoPage/NoTypeInfo Pass1 suppression, module/header/module transitions, no-XAML IFC
cleanup, static provider/consumer, and all 10 focused unit methods. NoPage/NoTypeInfo
are Pass1 checks, not suppressed-code application linking guarantees.

Its unfiltered unit job failed. One failure is missing Microsoft.Build.Utilities.Core;
others are legacy schema/type-collector/validation expectations. Upstream #11837 restores
the runtime/reference closure and repairs several tests; its own report still lists four
known succinct-collection failures. Do not attribute every old assertion to our module
change, or declare them fixed without new results.

Current source inventory after upstream modernization and the module additions is
309 `[TestMethod]` declarations and 5 `[Ignore]` attributes in compiled unit sources.
This is source inventory, not a VSTest execution count. Upstream re-enabled 28 DiffCodegen
comparisons, replacing the old 44 ignored comparison methods. The full runner must build
those regression inputs before execution, preserve all enabled tests and save discovery,
TRX, summaries and build binlogs. Do not regenerate masters just to silence a difference.

## Validation branch

`feat/xamlccppmodule/product-validation` holds the native fixture package pin, fixture
projection-mode cache, bootstrap requirements, workflows and modernized unit runner.
Focused execution only builds the unit prerequisites needed by its 10-method filter.
Full execution builds the upstream test solution, including generated-code comparison
inputs, and has no filter. Both use upstream payload staging and runsettings; no second
runtime-copy directory or replacement test csproj is introduced.

Windows results for this branch and the rebased product remain pending. The original
successful focused run does not validate the new tree. Interactive sample execution,
other-architecture module compilation and the complete unfiltered suite are separate
acceptance items.
