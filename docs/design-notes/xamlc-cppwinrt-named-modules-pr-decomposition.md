# XamlC named-module review and validation plan

## Validated implementation

The current implementation is on `feat/xamlccppmodule/product-validation`, based on
`feat/xamlccppmodule/product`. PR [#40](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/40)
holds the compiler changes, generated T4 companions, regression inputs, documentation
and fork validation infrastructure. The historical `phase1` and `phase2` branches are
preserved as checkpoints.

Each active XAML class owns an independent declaration module. `Application_Xaml.g.ixx`
is a pure re-export aggregator. BindingInfo and TypeInfo have separate independent
interfaces. Generated implementations remain ordinary `.cpp` translation units with
their textual system/STL headers before imports and no `import std`. C++/WinRT owns
the `winrt.<Namespace>` projection modules and producer scaffolding.

The original product and review branches predate this final architecture. In particular,
the old primary-interface/partition design and shared Support module are superseded.
Do not describe the old review tips as the implementation validated by PR #40.

## Review order

| Review PR | Scope | Dependency | Current status |
| --- | --- | --- | --- |
| [#37 bootstrap](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/37) | Initialization requirements | Independent | Existing draft; retain the small bootstrap scope |
| [#38 incremental](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/38) | Common compiler input/state ownership | Independent | Existing draft; review before module integration |
| [#39 modules](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/39) | Named-module compiler, targets and unit regressions | #38 | Existing draft predates the independent class-module architecture; extraction remains pending |
| [#36 docs/sample](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/36) | Architecture and developer sample | Modules | Existing draft must follow the final implementation |
| [#40 validation](https://github.com/hoshiizumiya/microsoft-ui-xaml/pull/40) | Final implementation and fork validation | Product | Source of the current implementation and test evidence |

Keep declaration ownership, semantic dependency closure, native build registration and
incremental lifetime together when extracting the module patch. The unit regressions
accompany the owning compiler changes. Generated C# companions remain with their
authoritative T4 templates. Fork workflows and native validation fixtures are separate
from the upstream product patch.

Upstream submission and reconciliation of the old review drafts are still separate work.
An earlier GitHub App submission attempt returned `Resource not accessible by integration`;
this document does not claim a successful upstream submission. PR #40's base and the
historical development branches are retained during validation.

## Verified evidence

[PR Build 38196092067](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/38196092067)
completed successfully on `a94f569764b58d251cf3be98bcec93f6c87c4605` on 2026-10-12.
T4 produced no successor commit. The reusable consumer used the synchronized checkout
SHA and the same run's `xaml-module-prereqs-x64chk` artifact.

| Gate | Verified result |
| --- | --- |
| Product builds | All six VS2022 configurations: x86/x64/arm64, Check and Release |
| Feature full suite | TRX: 364 total, 360 executed, 360 passed, zero failed |
| Predecessor full suite | TRX: 300 total, 296 executed, 292 passed, exactly four allowed historical failures |
| Upstream full suite | TRX: 300 total, 296 executed, 292 passed, exactly the same four allowed historical failures |
| Focused module tests | 21 executed, 21 passed |
| Native module consumers | x64, module and header modes, Debug and Release |
| Static libraries | Provider and cross-project consumer in module and header modes |
| Incremental graph | No-change, one-page change, removal/restoration, rename/restoration, suppression/restoration and header/module switching |
| Package integration | Real NuGet fixture and external product sample, Debug and Release |

The four historical failures are `WMC0155_ListViewCollectionCreatedWithSuccinctSyntax`,
`WMC0155_CheckSyntacticallyValidInput`, `WMC0155_CheckSyntacticallyInvalidInput` and
`WMC0155_ListViewDuplicateError`. The historical gate rejects missing or additional
failures and preserves TRX and failure manifests. The feature gate has no allowlist.

The TRX execution counts above are test-run evidence, not source-inventory counts.
NoPageCodeGen and NoTypeInfoCodeGen interface checks validate suppression of generated
declarations; they do not promise application linking after suppressing required code.
Six product architectures/configurations do not establish x86/arm64 named-module
consumer compilation: the native consumer validation in this run targets x64.
Interactive sample execution also remains a separate acceptance item.

## Subsequent changes

Any commit after the verified SHA requires its own run. The current follow-up repairs
multi-line succinct-collection diagnostics, adds direct parser boundary regressions,
and registers each XAML-owned object once in the Obj/Lib/Link input collections;
the result table above belongs to the earlier validated SHA until the follow-up completes.

The full runner builds the regression inputs, runs without a test filter and retains
discovery, TRX, summaries and binlogs. The focused runner exercises module tests with
their required prerequisites. Both use the upstream payload staging and runsettings.
Do not regenerate masters to hide an unexplained difference, or count queued, skipped,
cancelled or superseded validation steps as successful execution.

## Outstanding integration work

- Reconcile the old review drafts with the final independent-module architecture before
  upstream submission, keeping bootstrap/incremental/module/docs responsibilities clear.
- Keep C++/WinRT-owned provider-wrapper and projection-incremental defects distinct from
  XamlC fixes; fixture mitigations are not fixes to the third-party package.
- Verify the follow-up for duplicate object registration against the static-library
  and application consumers. The native runner now rejects LNK4042 warnings and saves
  a readable log alongside each binlog.
- Treat interactive sample execution and other-architecture native module compilation
  as unverified until their own evidence is available.

