// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
#include "pch.h"

#define WINRT_IMPORT_MODULE
#include "BindModel.h"
#include "BindModel.g.cpp"

namespace winrt::Simple::Models::implementation
{
    BindModel::BindModel()
        : m_items(single_threaded_observable_vector<Simple::Models::BindItem>())
    {
    }
}
