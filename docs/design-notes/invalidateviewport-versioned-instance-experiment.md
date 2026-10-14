# Versioned FrameworkElement.InvalidateViewport experiment

Base: `hoshiizumiya/microsoft-ui-xaml` `main` at
`895a8a7c0bf4b7946d401dabddf93f8bf9d002c1`.
Branch: `experiment/frameworkelement-invalidateviewport-v2`.

## API and ABI

Keep the existing version-1 public, protected, override, and factory interfaces.
The old protected ABI method remains `InvalidateViewport`, with its original signature
and slot. Its projected name becomes `InvalidateViewportProtected` through the existing
method_name/overload mechanism. Add model version 2, using WinUIContract.Experimental
(contract 12 on this baseline), rather than adding a slot to IFrameworkElement.
The existing feature-specific interface is also retained.

The generated modern IDL contains:

```idl
unsealed runtimeclass FrameworkElement : Microsoft.UI.Xaml.UIElement
{
    // Version-1 ABI unchanged; only the protected projection name is aliased.
    [method_name("InvalidateViewport")] protected void InvalidateViewportProtected();

    [contract(Microsoft.UI.Xaml.WinUIContract, 12)]
    {
        [method_name("InvalidateViewportPublic")] void InvalidateViewport();
    }

    // Existing Feature_ExperimentalApi interface remains unchanged.
};
```

The new default versioned interface is IFrameworkElement2. Its ABI entry point
is InvalidateViewportPublic, while its projected overload name is InvalidateViewport.
The model uses DXamlName("InvalidateViewportPublic") and
DXamlOverloadName("InvalidateViewport") to express this distinction using existing
generator support. The old protected method uses DXamlName("InvalidateViewport") and
DXamlOverloadName("InvalidateViewportProtected") to retain its ABI name while avoiding
a projected signature collision. No generator or template changes are needed.

```text
IFrameworkElementProtected::InvalidateViewport()
  -> FrameworkElement::InvalidateViewportImpl()

IFrameworkElement2::InvalidateViewportPublic()
  -> FrameworkElement::InvalidateViewportPublicImpl()
  -> FrameworkElement::InvalidateViewportImpl()
```

The new implementation consists only of the forwarding call. Scroller validation,
shutdown handling, and the core viewport invalidation remain in the existing method.
The generated version-2 interface uses the repository's existing forwarder_holder
pattern and adds a QI branch without removing the existing branches.

The intended source-level call is:

```cpp
element.InvalidateViewport();   // C++/WinRT
element->InvalidateViewport(); // C++/CX
element.InvalidateViewport();  // C#/WinRT
```

## CI validation

All IDL/T4 generation is performed by the branch's
`Sync T4 - InvalidateViewport experiment` GitHub Actions workflow.
No local generation is required or was performed for this experiment.

The final protected-alias variant passed the generation, ABI comparison, and all
three language compilation checks in
[Actions run 38526509159](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/38526509159).
For comparison, the unchanged-protected-projection variant failed C#/WinRT with
CS0540 in
[Actions run 38526140079](https://github.com/hoshiizumiya/microsoft-ui-xaml/actions/runs/38526140079).

The workflow compiles the same Sources.targets lists used by the instant compiler,
runs the repository's checked-in preprocessed T4 templates for core and phone, and
synchronizes output using the repository's own output manifest. It commits generated
output only after validation succeeds. The regular PR Build on the baseline has its
product-build matrix disabled; its green status would not establish product correctness.

Checks include:

- The generated FrameworkElement version-1 ABI declarations match the pinned main
  baseline after normalizing the protected projection alias.
- Generated declarations and QI retain IFrameworkElement and IFrameworkElementProtected
  and add IFrameworkElement2.
- Both generated ABI stubs call the expected implementation methods.
- A focused MIDL probe uses the exact generated public and protected declarations,
  then compiles direct C++/WinRT and C++/CX public calls.
- A before/after probe compares its version-1 interface GUID definitions and ABI vtables,
  including the effect of the protected overload alias.
- A C#/WinRT projection project uses the package version pinned in packages.config
  and compiles a public instance call.

The focused probe deliberately avoids the full product's external metadata dependencies.
It tests the metadata/projection naming mechanism; it is not a full Microsoft.UI.Xaml
product build or execution of the native layout tests. Public scroller/non-scroller
calls were also added to the existing native integration test for later product testing.

The initial experiment retained both projected names as InvalidateViewport. MIDL
emitted warning MIDL4066 and qualified the new runtimeclass metadata member with its
interface name. C++/WinRT and C++/CX public calls compiled, but the repository's
C#/WinRT 2.1.1 emitted an explicit interface implementation without declaring that
interface on the class, producing CS0540. This is why the final experiment aliases
the old protected projection while preserving its original ABI name and slot.

The alias is an intentional metadata/source change. Code explicitly calling the old
protected interface through a language projection must use InvalidateViewportProtected.
Existing binaries still call the old InvalidateViewport ABI slot. Runtimeclass callers
can use the new public InvalidateViewport method. Preserving the old projected name
as well would require additional C#/WinRT generator support; this experiment does not
modify that external generator. A complete product build and native test execution
remain separate validation tasks.

## Changed files

Handwritten source and tests:

- dxaml/xcp/tools/XCPTypesAutoGen/XamlOM/Model/FrameworkElement.cs
- dxaml/xcp/dxaml/lib/FrameworkElement_Partial.h
- dxaml/xcp/dxaml/lib/FrameworkElement_partial.cpp
- dxaml/test/native/external/framework/layout/LayoutManagerIntegrationTests.cpp

CI-generated output:

- dxaml/xcp/dxaml/idl/winrt/core/microsoft.ui.xaml.coretypes.idl
- dxaml/xcp/dxaml/lib/synonyms.g.h
- dxaml/xcp/dxaml/lib/winrtgeneratedclasses/FrameworkElement.g.h
- dxaml/xcp/dxaml/lib/winrtgeneratedclasses/FrameworkElement.g.cpp
- dxaml/xcp/components/metadata/inc/Indexes.g.h
- dxaml/xcp/plat/win/desktop/Microsoft-Windows-XAML-ETW.man

Experiment support:

- .github/workflows/sync-t4-viewport.yml
- .github/scripts/sync-t4-viewport.ps1
- .github/scripts/check-viewport-csharp.ps1
- docs/design-notes/invalidateviewport-versioned-instance-experiment.md

## Review conclusion

The experiment tests adding a versioned public instance entry point while retaining
the old protected ABI through existing XamlOM name/overload annotations. The protected
projection alias is necessary for the tested C#/WinRT generator. This remains an
experimental API, pending complete product validation and API review/release assignment.
