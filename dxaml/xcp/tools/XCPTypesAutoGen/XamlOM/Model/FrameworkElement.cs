// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE in the project root for license information.
using OM;
using System;
using Windows.Foundation;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Markup;
using XamlOM;

namespace Microsoft.UI.Xaml
{
    [Platform(2, typeof(Microsoft.UI.Xaml.WinUIContract), Microsoft.UI.Xaml.WinUIContract.Experimental)]
    partial class FrameworkElement
    {
        [NativeMethod("CFrameworkElement", "ActualTheme")]
        [NativeStorageType(OM.ValueType.valueEnum)]
        [ReadOnly]
        public Microsoft.UI.Xaml.ElementTheme ActualTheme
        {
            get;
            private set;
        }

        [EventFlags(UseEventManager = true)]
        public event Windows.Foundation.TypedEventHandler<FrameworkElement, Windows.Foundation.Object> ActualThemeChanged;

        [EventFlags(UseEventManager = true)]
        public event Windows.Foundation.TypedEventHandler<FrameworkElement, Microsoft.UI.Xaml.EffectiveViewportChangedEventArgs> EffectiveViewportChanged;

        [EventFlags(UseEventManager = true)]
        internal event Windows.Foundation.TypedEventHandler<FrameworkElement, Windows.Foundation.Object> HighContrastChanged;

        [CodeGen(CodeGenLevel.IdlAndStub)]
        [DXamlName("InvalidateViewport")]
        [DXamlOverloadName("InvalidateViewportProtected")]
        protected void InvalidateViewport()
        {
        }

        // Preserve the shipped protected ABI name, but give its projection an alias
        // to avoid a same-signature collision in C#/WinRT. The new public projection
        // keeps the natural name and has a distinct ABI name on version 2.
        [Version(2)]
        [CodeGen(CodeGenLevel.IdlAndStub)]
        [DXamlName("InvalidateViewportPublic")]
        [DXamlOverloadName("InvalidateViewport")]
        public void InvalidateViewportPublic()
        {
        }
    }
}
