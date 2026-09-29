// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#include "pch.h"

// Direct-import smoke test for the project-level XAML umbrella module.
// Normal application sources must not need this import; their generated
// component .g.h includes the corresponding .xaml.g.h shim automatically.
#define WINRT_IMPORT_MODULE
import Simple.Application_Xaml;

// Importing the umbrella must make the exported BindingInfo and TypeInfo definitions
// semantically usable, not merely make the module name resolvable. These complete-type
// checks exercise STL-bearing layouts, winrt::implements bases and the legacy-COM
// IXamlUserType base through the consumer-side IFC.
static_assert(sizeof(winrt::Simple::implementation::XamlBindings) > 0);
static_assert(sizeof(winrt::Simple::implementation::XamlTypeInfoProvider) > 0);
static_assert(sizeof(winrt::Simple::implementation::IXamlUserType) > 0);
