// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
using System.Reflection;

namespace Win8Xaml.CompilerProxies
{
    /// <summary>
    /// Proxy for Microsoft.UI.Xaml.Markup.Compiler.DirectUI.ReflectionHelper.
    /// Releases the custom-attribute cache that otherwise pins assemblies from disposed universes.
    /// </summary>
    public static class ReflectionHelper
    {
        static readonly MethodInfo _release;

        static ReflectionHelper()
        {
            var helper = new ProxyHelper("Microsoft.UI.Xaml.Markup.Compiler.DirectUI.ReflectionHelper");
            _release = helper.GetMethod("Release", BindingFlags.NonPublic | BindingFlags.Static);
        }

        public static void Release()
        {
            _release.Invoke(null, null);
        }
    }
}
