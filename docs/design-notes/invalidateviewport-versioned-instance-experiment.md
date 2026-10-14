# Versioned FrameworkElement.InvalidateViewport experiment

Base: `hoshiizumiya/microsoft-ui-xaml` `main` at
`895a8a7c0bf4b7946d401dabddf93f8bf9d002c1`.
Branch: `experiment/frameworkelement-invalidateviewport-v2`.

## API and ABI

Keep the existing version-1 public, protected, override, and factory interfaces.
The old protected declaration remains exactly `protected void InvalidateViewport()`
in XamlOM and generated IDL. Add model version 2, using WinUIContract.Experimental
(contract 12 on this baseline), rather than adding a slot to IFrameworkElement.
The existing feature-specific interface is also retained.

The generated modern IDL contains:

```idl
unsealed runtimeclass FrameworkElement : Microsoft.UI.Xaml.UIElement
{
    // All existing version-1 members remain unchanged.
    protected void InvalidateViewport();

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
generator support. No generator or template changes are needed.

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
```

## CI validation

All IDL/T4 generation is performed by the branch's
`Sync T4 - InvalidateViewport experiment` GitHub Actions workflow.
No local generation is required or was performed for this experiment.

The workflow compiles the same Sources.targets lists used by the instant compiler,
runs the repository's checked-in preprocessed T4 templates for core and phone, and
synchronizes output using the repository's own output manifest. It commits generated
output only after validation succeeds. The regular PR Build on the baseline has its
product-build matrix disabled; its green status would not establish product correctness.

Checks include:

- The generated FrameworkElement version-1 IDL portion matches the pinned main baseline.
- Generated declarations and QI retain IFrameworkElement and IFrameworkElementProtected
  and add IFrameworkElement2.
- Both generated ABI stubs call the expected implementation methods.
- A focused MIDL probe uses the exact generated public declaration alongside the
  existing protected signature, then compiles direct C++/WinRT and C++/CX public calls.
- A before/after probe compares existing interface GUID definitions and ABI vtables.

The focused probe deliberately avoids the full product's external metadata dependencies.
It tests the metadata/projection naming mechanism; it is not a full Microsoft.UI.Xaml
product build or execution of the native layout tests. Public scroller/non-scroller
calls were also added to the existing native integration test for later product testing.

MIDL emits warning MIDL4066 because the runtimeclass contains colliding projected
member names. It qualifies the new runtimeclass metadata member with its interface
name. This warning does not prevent the tested C++/WinRT or C++/CX public calls from
compiling. C#/WinRT and a complete product build still need separate validation.

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
- docs/design-notes/invalidateviewport-versioned-instance-experiment.md

## Review conclusion

The experiment demonstrates that the existing XamlOM name/overload annotations can
add a versioned public instance entry point while retaining the old protected ABI.
A static UIElement helper is not required to get through the tested generation and
C++ projection stages. This remains an experimental API, pending complete product
validation, other-language projection checks, and API review/release assignment.
