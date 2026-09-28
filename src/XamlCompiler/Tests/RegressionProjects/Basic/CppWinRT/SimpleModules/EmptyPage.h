// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
#pragma once

#include "EmptyPage.g.h"

namespace winrt::Simple::implementation
{
    struct EmptyPage : EmptyPageT<EmptyPage>
    {
        EmptyPage();
    };
}

namespace winrt::Simple::factory_implementation
{
    struct EmptyPage : EmptyPageT<EmptyPage, implementation::EmptyPage>
    {
    };
}
