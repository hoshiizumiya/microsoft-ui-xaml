// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

import Simple.Application_Xaml;
import Simple.Application_Xaml.BindingInfo;
import Simple.Application_Xaml.TypeInfo;

static_assert(sizeof(winrt::Simple::implementation::MainPageT<struct ModuleSmokeMainPage>) > 0);
static_assert(sizeof(winrt::Simple::implementation::XamlBindings) > 0);
static_assert(sizeof(winrt::Simple::implementation::XamlTypeInfoProvider) > 0);
static_assert(sizeof(winrt::Simple::implementation::IXamlUserType) > 0);
