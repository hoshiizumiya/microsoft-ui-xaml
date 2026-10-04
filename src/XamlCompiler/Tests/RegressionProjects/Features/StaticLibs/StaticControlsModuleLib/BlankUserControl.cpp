// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
#include "pch.h"

#ifdef XAML_FIXTURE_MODULES
#define WINRT_IMPORT_MODULE
#endif
#include "BlankUserControl.h"

namespace winrt::StaticControlsModuleLib::implementation
{
    BlankUserControl::BlankUserControl()
    {
        InitializeComponent();
    }
}
