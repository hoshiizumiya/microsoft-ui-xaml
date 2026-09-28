// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
#include "pch.h"

#define WINRT_IMPORT_MODULE
#include "BlankUserControl.h"

namespace winrt::StaticControlsModuleLib::implementation
{
    BlankUserControl::BlankUserControl()
    {
        InitializeComponent();
    }
}
