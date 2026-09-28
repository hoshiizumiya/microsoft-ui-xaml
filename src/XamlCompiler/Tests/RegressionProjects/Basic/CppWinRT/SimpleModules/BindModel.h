// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
#pragma once

#include "BindModel.g.h"

namespace winrt::Simple::Models::implementation
{
    struct BindModel : BindModelT<BindModel>
    {
        BindModel();

        Windows::Foundation::Collections::IObservableVector<Simple::Models::BindItem> Items() const noexcept
        {
            return m_items;
        }

    private:
        Windows::Foundation::Collections::IObservableVector<Simple::Models::BindItem> m_items{ nullptr };
    };
}

namespace winrt::Simple::Models::factory_implementation
{
    struct BindModel : BindModelT<BindModel, implementation::BindModel>
    {
    };
}
