// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Win8Xaml.CompilerProxies;

namespace UnitTests
{
    [TestClass]
    public class CppWinRTModuleTests
    {
        [TestMethod]
        public void ProjectionDependency_LowersNamespaceToHeaderAndModule()
        {
            const string projectionNamespace = "Microsoft.UI.Xaml.Controls";

            Assert.AreEqual(
                "winrt/Microsoft.UI.Xaml.Controls.h",
                CppWinRTProjectionDependency.GetHeaderFile(projectionNamespace));
            Assert.AreEqual(
                "winrt.Microsoft.UI.Xaml.Controls",
                CppWinRTProjectionDependency.GetModuleName(projectionNamespace));
        }

        [TestMethod]
        public void ProjectContext_PropagatesNamedModuleMode()
        {
            var context = new CodeGeneratorProjectContext(new Version(KnownVersions.Latest));
            context.UseCppWinRTNamedModules = true;

            Assert.IsTrue(context.ProjectInfo.UseCppWinRTNamedModules);
        }
    }
}
