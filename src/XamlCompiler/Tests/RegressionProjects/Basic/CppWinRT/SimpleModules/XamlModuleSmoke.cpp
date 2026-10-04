// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

// Module-only consumption of the root declaration aggregator.
// Ordinary handwritten sources retain their own include/import strategy.
import Simple.Application_Xaml;

// Importing the umbrella must make the exported BindingInfo and TypeInfo definitions
// semantically usable, not merely make the module name resolvable. These complete-type
// checks exercise STL-bearing layouts, winrt::implements bases and the legacy-COM
// IXamlUserType base through the consumer-side IFC.
static_assert(sizeof(winrt::Simple::implementation::XamlBindings) > 0);
static_assert(sizeof(winrt::Simple::implementation::XamlTypeInfoProvider) > 0);
static_assert(sizeof(winrt::Simple::implementation::IXamlUserType) > 0);
