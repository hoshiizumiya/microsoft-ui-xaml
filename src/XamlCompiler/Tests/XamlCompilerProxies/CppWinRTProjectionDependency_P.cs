// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Reflection;

namespace Win8Xaml.CompilerProxies
{
    public static class CppWinRTProjectionDependency
    {
        static readonly ProxyHelper _projectionDependencyType;
        static readonly MethodInfo _getHeaderFile;
        static readonly MethodInfo _getModuleName;

        static CppWinRTProjectionDependency()
        {
            _projectionDependencyType = new ProxyHelper("Microsoft.UI.Xaml.Markup.Compiler.CodeGen.CppWinRTProjectionDependency");
            _getHeaderFile = _projectionDependencyType.GetStaticMethod("GetHeaderFile", 1);
            _getModuleName = _projectionDependencyType.GetStaticMethod("GetModuleName", 1);
        }

        public static string GetHeaderFile(string projectionNamespace)
        {
            return (string)_getHeaderFile.Invoke(null, new object[] { projectionNamespace });
        }

        public static string GetModuleName(string projectionNamespace)
        {
            return (string)_getModuleName.Invoke(null, new object[] { projectionNamespace });
        }
    }
}
