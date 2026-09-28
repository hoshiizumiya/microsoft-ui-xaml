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
        public void XamlModuleNames_AreQualifiedAndCollisionResistant()
        {
            Assert.AreEqual(
                "OpenNet.Application_Xaml",
                CppWinRTProjectionDependency.GetXamlPrimaryModuleName("OpenNet"));
            Assert.AreEqual(
                "Application_Xaml",
                CppWinRTProjectionDependency.GetXamlPrimaryModuleName(String.Empty));
            Assert.AreEqual(
                "OpenNet.UI.Pages.MainPage",
                CppWinRTProjectionDependency.GetXamlPartitionName("OpenNet::UI::Pages::MainPage"));
            Assert.AreEqual(
                "OpenNet.Application_Xaml:OpenNet.UI.Pages.MainPage",
                CppWinRTProjectionDependency.GetXamlPartitionModuleName("OpenNet", "OpenNet::UI::Pages::MainPage"));

            // Legacy helper contracts remain stable until checked-in T4-generated C# is regenerated.
            Assert.AreEqual(
                "OpenNet.UI.Pages.MainPage_Xaml",
                CppWinRTProjectionDependency.GetXamlModuleName("OpenNet.UI.Pages.MainPage"));
            Assert.AreEqual(
                "OpenNet.XamlTypeInfo_Xaml",
                CppWinRTProjectionDependency.GetProjectXamlModuleName("OpenNet", "XamlTypeInfo"));
        }

        [TestMethod]
        public void ProjectContext_PropagatesNamedModuleMode()
        {
            var context = new CodeGeneratorProjectContext(new Version(KnownVersions.Latest));
            context.UseCppWinRTNamedModules = true;

            Assert.IsTrue(context.ProjectInfo.UseCppWinRTNamedModules);
        }

        [TestMethod]
        public void ProjectContext_StoresCompleteXamlPartitionSet()
        {
            var context = new CodeGeneratorProjectContext(new Version(KnownVersions.Latest));
            context.ProjectInfo.XamlClassNames = new[]
            {
                "OpenNet.App",
                "OpenNet.UI.Pages.MainPage",
            };

            CollectionAssert.AreEqual(
                new[] { "OpenNet.App", "OpenNet.UI.Pages.MainPage" },
                new System.Collections.Generic.List<string>(context.ProjectInfo.XamlClassNames));
        }


        [TestMethod]
        public void EmptyPage_StillRequiresGeneratedScaffoldingProjections()
        {
            const string xaml = @"
<Page
    xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
    xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
    x:Class='TestApp.EmptyPage' />";

            var helper = new TestHelper();
            var schema = helper.LoadSchema(SchemaMode.ManagedRuntime);
            var domRoot = helper.LoadXamlDom(xaml, schema);
            var codeInfo = helper.HarvestClassCodeInfo(".", domRoot, true, false);
            var projectInfo = new XamlProjectInfo
            {
                ClassToHeaderFileMap = new System.Collections.Generic.Dictionary<string, string>(),
            };
            var definition = new PageDefinition(projectInfo, new XamlSchemaCodeInfo())
            {
                CodeInfo = codeInfo,
            };

            CollectionAssert.AreEquivalent(
                new[]
                {
                    "Windows.Foundation",
                    "Microsoft.UI.Xaml",
                    "Microsoft.UI.Xaml.Controls.Primitives",
                    "Microsoft.UI.Xaml.Markup",
                },
                definition.NeededCppWinRTProjectionNamespaces);
        }
    }
}
