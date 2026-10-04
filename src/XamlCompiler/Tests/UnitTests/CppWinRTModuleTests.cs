// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System;
using System.Collections.Generic;
using System.Linq;
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
        public void ProjectionDependency_RecursesThroughGenericArguments()
        {
            var namespaces = CppWinRTProjectionDependency.GetNamespaces(
                typeof(ProjectionDependencyFixtures.Outer.Container<
                    ProjectionDependencyFixtures.Middle.Envelope<
                        ProjectionDependencyFixtures.Inner.Payload>>));

            CollectionAssert.AreEquivalent(
                new[]
                {
                    "ProjectionDependencyFixtures.Outer",
                    "ProjectionDependencyFixtures.Middle",
                    "ProjectionDependencyFixtures.Inner",
                },
                namespaces);
        }

        [TestMethod]
        public void ProjectionDependency_UsesNamespaceFallbackForUnresolvedPass1Type()
        {
            var namespaces = CppWinRTProjectionDependency.GetNamespaces(null, "Simple");

            CollectionAssert.AreEqual(
                new[] { "Simple" },
                new System.Collections.Generic.List<string>(namespaces));

            var knownPrimitiveNamespaces = CppWinRTProjectionDependency.GetNamespaces(typeof(int), "Simple");
            Assert.AreEqual(0, new System.Collections.Generic.List<string>(knownPrimitiveNamespaces).Count);
        }

        [TestMethod]
        public void ProjectionDependency_DoesNotTreatProjectedPrimitiveAsNamespaceDependency()
        {
            var namespaces = CppWinRTProjectionDependency.GetNamespaces(
                typeof(ProjectionDependencyFixtures.Outer.Container<int>));

            CollectionAssert.AreEquivalent(
                new[] { "ProjectionDependencyFixtures.Outer" },
                namespaces);
        }

        [TestMethod]
        public void ClassModuleIdentity_PreservesFullNamespaceAndKeywordSegments()
        {
            Assert.AreEqual("OpenNet.Application_Xaml", CppWinRTProjectionDependency.GetXamlPrimaryModuleName("OpenNet"));
            Assert.AreEqual("Application_Xaml", CppWinRTProjectionDependency.GetXamlPrimaryModuleName(String.Empty));
            Assert.AreEqual("OpenNet.Application_Xaml.Class.C__0056iews.C__004dain_0050age", CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Views::MainPage"));
            Assert.AreNotEqual(CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Views.MainPage"), CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Controls.MainPage"));
            Assert.AreNotEqual(CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "A_B.C"), CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "A.B_C"));
            Assert.AreEqual("OpenNet.Application_Xaml.Class.C_export.C_module", CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "export.module"));
            Assert.AreNotEqual("OpenNet.Application_Xaml.Support", CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Support"));
            Assert.IsFalse(String.Equals(
                CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Views.MainPage"),
                CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "views.MainPage"),
                StringComparison.OrdinalIgnoreCase));
        }

        [TestMethod]
        public void Interface_PackagesAnOrdinaryHeaderWithSemanticReExports()
        {
            string text = CppWinRTProjectionDependency.WriteInterface("Test.Page", new[] { "Microsoft.UI.Xaml", "Windows.Foundation", "Microsoft.UI.Xaml" }, new[] { "Page.xaml.g.h" });
            StringAssert.Contains(text, "module;");
            StringAssert.Contains(text, "export module Test.Page;");
            StringAssert.Contains(text, "export import winrt.Microsoft.UI.Xaml;");
            Assert.AreEqual(1, text.Split(new[] { "export import winrt.Microsoft.UI.Xaml;" }, StringSplitOptions.None).Length - 1);
            StringAssert.Contains(text, "#define XAML_IMPL_MODULE");
            StringAssert.Contains(text, "#include \"Page.xaml.g.h\"");
            StringAssert.Contains(text, "#undef XAML_IMPL_MODULE");
            Assert.IsFalse(text.Contains("WINRT_XAML"));
            Assert.IsFalse(text.Contains("export module Test.Page:"));
        }

        [TestMethod]
        public void Aggregator_OnlyReExportsIndependentInterfacesFromTheFullClassSet()
        {
            string text = CppWinRTProjectionDependency.WriteAggregator("Test", new[] { "Test.SecondPage", "Test.App", "Test.MainPage", "Test.MainPage" });
            StringAssert.Contains(text, "export import Test.Application_Xaml.Support;");
            foreach (var name in new[] { "Test.App", "Test.MainPage", "Test.SecondPage" })
            {
                StringAssert.Contains(text, "export import " + CppWinRTProjectionDependency.GetXamlClassModuleName("Test", name) + ";");
            }
            Assert.IsFalse(text.Contains("#include"));
            Assert.IsFalse(text.Contains("namespace"));
            string removed = CppWinRTProjectionDependency.WriteAggregator("Test", new[] { "Test.App", "Test.MainPage" });
            Assert.IsFalse(removed.Contains("SecondPage"));
        }

        private static List<FileNameAndContentPair> GeneratePage(bool buildModules, bool app = false)
        {
            var helper = new TestHelper();
            var context = new CodeGeneratorProjectContext(new Version(KnownVersions.Latest), "Test")
            {
                RootNamespace = "Test", IsPass1 = true, IsApplication = app, BuildXamlModules = buildModules
            };
            string element = app ? "Application" : "Page";
            string xaml = "<" + element + " xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' x:Class='Test.MainPage' />";
            return helper.GenerateCodeBehind(context, new List<string> { xaml }, helper.LoadSchema(SchemaMode.ManagedRuntime), CodeGenLanguage.CppWinRT);
        }

        [TestMethod]
        public void Header_IsModuleAwareAndIdenticalWithModulesEnabledOrDisabled()
        {
            var traditional = GeneratePage(false);
            var modules = GeneratePage(true);
            Assert.AreEqual(1, traditional.Count);
            Assert.AreEqual(2, modules.Count);
            string header = traditional.Single().Contents;
            Assert.AreEqual(header, modules.Single(file => file.FileName.EndsWith(".h")).Contents);
            StringAssert.Contains(header, "#ifndef XAML_IMPL_MODULE");
            StringAssert.Contains(header, "#include <winrt/Microsoft.UI.Xaml.h>");
            StringAssert.Contains(header, "#define XAML_EXPORT export extern \"C++\"");
            StringAssert.Contains(header, "struct MainPageT");
            Assert.IsFalse(header.Contains("export module"));
            Assert.IsFalse(header.Contains("Application_Xaml"));
            Assert.IsFalse(header.Contains("WINRT_XAML_SKIP_BODY"));
            string module = modules.Single(file => file.FileName.EndsWith(".ixx")).Contents;
            StringAssert.Contains(module, "export module Test.Application_Xaml.Class.C__0054est.C__004dain_0050age;");
            StringAssert.Contains(module, "export import winrt.Microsoft.UI.Xaml.Controls;");
            Assert.IsFalse(module.Contains("Controls.Primitives"));
        }

        [TestMethod]
        public void App_PreservesInlineMethodsAndDefersHandwrittenProviderInstantiation()
        {
            string header = GeneratePage(true, true).Single(file => file.FileName.EndsWith(".h")).Contents;
            StringAssert.Contains(header, "XamlAppMetadataProvider<D>::type");
            StringAssert.Contains(header, "winrt::make_self<XamlMetaDataProvider>()");
            Assert.IsFalse(header.Contains("AppT();"));
            Assert.IsFalse(header.Contains("~AppT();"));
            Assert.IsFalse(header.Contains("export module"));
        }

        [TestMethod]
        public void TypeInfoConsumer_IncludesLocalDeclarationsBeforeProjectionAndRootImports()
        {
            var helper = new TestHelper();
            var project = new XamlProjectInfo
            {
                RootNamespace = "Test", ProjectName = "Test", TargetPlatformMinVersion = new Version(KnownVersions.Latest),
                ClassToHeaderFileMap = new Dictionary<string, string> { { "Test.MainPage", "MainPage.xaml.h" }, { "Test.SecondPage", "SecondPage.xaml.h" } }
            };
            project.SetEmptyAdditionalXamlTypeInfoIncludes();
            var schema = new XamlSchemaCodeInfo();
            string text = helper.GenerateTypeInfo(false, schema, project, new ClassName("Test.App"), CodeGenLanguage.CppWinRT).Single(file => file.FileName == "XamlTypeInfo.g.cpp").Contents;
            int firstImport = text.IndexOf("import winrt.", StringComparison.Ordinal);
            int rootImport = text.IndexOf("import Test.Application_Xaml;", StringComparison.Ordinal);
            foreach (string header in new[] { "MainPage.xaml.h", "SecondPage.xaml.h" })
            {
                int local = text.IndexOf("#include \"" + header + "\"", StringComparison.Ordinal);
                Assert.IsTrue(local >= 0 && local < firstImport && local < rootImport);
            }
            Assert.IsTrue(text.IndexOf("#include <vector>", StringComparison.Ordinal) < firstImport);
            StringAssert.Contains(text, "#ifdef XAML_USE_MODULE");
            Assert.IsFalse(text.Contains("export module"));
            Assert.IsFalse(text.Contains("ModulePreamble"));
            project.BuildXamlModules = true;
            Assert.AreEqual(text, helper.GenerateTypeInfo(false, schema, project, new ClassName("Test.App"), CodeGenLanguage.CppWinRT).Single(file => file.FileName == "XamlTypeInfo.g.cpp").Contents);
            project.PrecompiledHeaderFile = "pch.h";
            foreach (bool pass1 in new[] { true, false })
            {
                foreach (var source in helper.GenerateTypeInfo(pass1, schema, project, new ClassName("Test.App"), CodeGenLanguage.CppWinRT).Where(file => file.FileName.EndsWith(".cpp", StringComparison.Ordinal)))
                {
                    Assert.IsFalse(source.Contents.Contains("pch.h"));
                }
            }
            project.BuildXamlModules = false;
            foreach (bool pass1 in new[] { true, false })
            {
                foreach (var source in helper.GenerateTypeInfo(pass1, schema, project, new ClassName("Test.App"), CodeGenLanguage.CppWinRT).Where(file => file.FileName.EndsWith(".cpp", StringComparison.Ordinal)))
                {
                    StringAssert.Contains(source.Contents, "#include \"pch.h\"");
                    Assert.IsFalse(source.Contents.Contains("#ifndef XAML_USE_MODULE"));
                }
            }
        }

        [TestMethod]
        public void ProjectionDependency_UnwrapsJaggedGenericArrays()
        {
            CollectionAssert.AreEquivalent(new[] { "ProjectionDependencyFixtures.Outer", "ProjectionDependencyFixtures.Inner" }, CppWinRTProjectionDependency.GetNamespaces(typeof(ProjectionDependencyFixtures.Outer.Container<ProjectionDependencyFixtures.Inner.Payload[]>[][])));
        }

        [TestMethod]
        public void NoTypeInfoCodeGen_SuppressesTypeInfoSupportDeclarations()
        {
            var projectInfo = new XamlProjectInfo();
            Assert.IsTrue(projectInfo.ShouldGenerateTypeInfoCode);

            projectInfo.SetCodeGenFlags("NoTypeInfoCodeGen");

            Assert.IsFalse(projectInfo.ShouldGenerateTypeInfoCode);
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

        [TestMethod]
        public void PageProjectionDependency_ToleratesUnresolvedBindPathValueType()
        {
            const string xaml = @"
<Page
    xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
    xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
    x:Class='TestApp.BindingPage'>
    <Grid>
        <Button x:Name='source' />
        <TextBlock Text='{x:Bind source.Tag}' />
    </Grid>
</Page>";

            var helper = new TestHelper();
            var schema = helper.LoadSchema(SchemaMode.ManagedRuntime);
            var domRoot = helper.LoadXamlDom(xaml, schema);
            var codeInfo = helper.HarvestClassCodeInfo(".", domRoot, true, false);
            var fileCodeInfo = helper.HarvestFileCodeInfo(".", true, codeInfo, domRoot);
            codeInfo.AddXamlFileInfo(fileCodeInfo);

            Assert.IsTrue(codeInfo.BindUniverses.Count > 0);
            codeInfo.BindUniverses[0].AddUnresolvedRootStepForTest("__unresolved");

            var projectInfo = new XamlProjectInfo
            {
                ClassToHeaderFileMap = new System.Collections.Generic.Dictionary<string, string>(),
            };
            var definition = new PageDefinition(projectInfo, new XamlSchemaCodeInfo())
            {
                CodeInfo = codeInfo,
            };

            CollectionAssert.Contains(
                definition.NeededCppWinRTProjectionNamespaces,
                "Microsoft.UI.Xaml");
        }
    }
}


namespace ProjectionDependencyFixtures.Outer
{
    internal sealed class Container<T>
    {
    }
}

namespace ProjectionDependencyFixtures.Middle
{
    internal sealed class Envelope<T>
    {
    }
}

namespace ProjectionDependencyFixtures.Inner
{
    internal sealed class Payload
    {
    }
}
