// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
#include "pch.h"

#define WINRT_IMPORT_MODULE
#include "EmptyPage.h"
#include "EmptyPage.g.cpp"

namespace winrt::Simple::implementation
{
    EmptyPage::EmptyPage()
    {
        InitializeComponent();
    }
}
