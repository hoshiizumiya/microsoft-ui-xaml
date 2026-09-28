// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

// Direct-import smoke test for the project-level XAML umbrella module.
// Normal application sources must not need this import; their generated
// component .g.h includes the corresponding .xaml.g.h shim automatically.
#define WINRT_IMPORT_MODULE
import Simple.Application_Xaml;

static_assert(true);
