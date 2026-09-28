// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
#pragma once

#include "BindTarget.g.h"

namespace winrt::Simple::Targets::implementation
{
    struct BindTarget : BindTargetT<BindTarget>
    {
        BindTarget() = default;
    };
}

namespace winrt::Simple::Targets::factory_implementation
{
    struct BindTarget : BindTargetT<BindTarget, implementation::BindTarget>
    {
    };
}
