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
        public void ClassModuleIdentity_PreservesReadableValidSegmentsAndEscapesKeywords()
        {
            Assert.AreEqual("OpenNet.Application_Xaml", CppWinRTProjectionDependency.GetXamlPrimaryModuleName("OpenNet"));
            Assert.AreEqual("Application_Xaml", CppWinRTProjectionDependency.GetXamlPrimaryModuleName(String.Empty));
            Assert.AreEqual("OpenNet.Application_Xaml.Views.MainPage", CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Views::MainPage"));
            Assert.AreEqual("OpenNet.Application_Xaml.Views.MainPage", CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "OpenNet.Views.MainPage"));
            Assert.AreNotEqual(CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Views.MainPage"), CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Controls.MainPage"));
            Assert.AreNotEqual(CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "A_B.C"), CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "A.B_C"));
            StringAssert.StartsWith(CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "export.module"), "OpenNet.Application_Xaml.__XamlEscaped_");
            Assert.AreEqual("OpenNet.Application_Xaml.Support", CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Support"));
            Assert.AreNotEqual(
                CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "Views.MainPage"),
                CppWinRTProjectionDependency.GetXamlClassModuleName("OpenNet", "views.MainPage"));
        }

        [TestMethod]
        public void ClassModuleIdentity_HandlesUnicodeNestedNamespacesAndDifferentProjectRoot()
        {
            var classes = new[] { "Views.MainPage", "Controls.MainPage", "A_B.C", "A.B_C", "export.module", "应用.视图.主页", "Other.Nested.Views.MainPage", "Other.App", "Other._0056iews.MainPage" };
            var identities = classes.Select(name => CppWinRTProjectionDependency.GetXamlClassModuleName("Project", name)).ToArray();
            Assert.AreEqual(classes.Length, identities.Distinct(StringComparer.Ordinal).Count());
            foreach (var identity in identities)
            {
                StringAssert.StartsWith(identity, "Project.Application_Xaml.");
                Assert.IsFalse(identity.Contains(".Class."));
            }
            Assert.AreEqual("应用.Application_Xaml", CppWinRTProjectionDependency.GetXamlPrimaryModuleName("应用"));
            Assert.AreEqual("Project.Application_Xaml.应用.视图.主页", CppWinRTProjectionDependency.GetXamlClassModuleName("Project", "应用.视图.主页"));
            Assert.AreEqual(CppWinRTProjectionDependency.GetXamlClassModuleName("Project", "应用.视图.主页"), CppWinRTProjectionDependency.GetXamlClassModuleName("Project", "应用::视图::主页"));
        }

        [TestMethod]
        public void RootModuleIdentity_UsesDeterministicFallbackForInvalidProjectNamespace()
        {
            foreach (var empty in new[] { null, "", " " })
            {
                Assert.AreEqual("Application_Xaml", CppWinRTProjectionDependency.GetXamlPrimaryModuleName(empty));
            }
            var invalid = new[] { "1Project", "Bad-Root", "A..B", "export.module", ".Root", "Root." };
            var identities = invalid.Select(CppWinRTProjectionDependency.GetXamlPrimaryModuleName).ToArray();
            Assert.AreEqual(invalid.Length, identities.Distinct(StringComparer.Ordinal).Count());
            for (int i = 0; i < invalid.Length; i++)
            {
                StringAssert.StartsWith(identities[i], "XamlProject.__XamlEscaped_");
                Assert.AreEqual(identities[i], CppWinRTProjectionDependency.GetXamlPrimaryModuleName(invalid[i]));
            }
        }

        [TestMethod]
        public void EarlyModuleGraph_DoesNotReadUninitializedProjectInfo()
        {
            CollectionAssert.AreEqual(new[] { false, false }, CppWinRTProjectionDependency.GetCodeGenerationDecisionsBeforeProjectInfo("Nothing"));
            CollectionAssert.AreEqual(new[] { true, false }, CppWinRTProjectionDependency.GetCodeGenerationDecisionsBeforeProjectInfo("NoPageCodeGen"));
            CollectionAssert.AreEqual(new[] { false, true }, CppWinRTProjectionDependency.GetCodeGenerationDecisionsBeforeProjectInfo("NoTypeInfoCodeGen"));
        }

        [TestMethod]
        public void DeclarationDependencies_DoNotTreatUnharvestedModelAsEmpty()
        {
            var definition = new PageDefinition(new XamlProjectInfo(), new XamlSchemaCodeInfo())
            {
                CodeInfo = new XamlClassCodeInfo("Test.NotHarvested", false)
            };
            try
            {
                var namespaces = definition.DeclarationCppWinRTProjectionNamespaces;
                Assert.Fail("Unharvested declaration dependencies must report an invalid lifecycle state.");
            }
            catch (System.Reflection.TargetInvocationException exception)
            {
                Assert.IsInstanceOfType(exception.InnerException, typeof(InvalidOperationException));
                StringAssert.Contains(exception.InnerException.ToString(), "must be harvested");
            }
        }

        [TestMethod]
        public void EmptyDeclarations_AreHarvestedBeforeDependencyCollection()
        {
            var helper = new TestHelper();
            var schema = helper.LoadSchema(SchemaMode.ManagedRuntime);
            foreach (var element in new[] { "Application", "Page", "UserControl", "ResourceDictionary" })
            {
                var context = new CodeGeneratorProjectContext(new Version(KnownVersions.Latest), "Test")
                {
                    RootNamespace = "Project", IsPass1 = true, IsApplication = element == "Application", BuildXamlModules = true
                };
                string xaml = "<" + element + " xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' x:Class='DifferentRoot.Empty" + element + "' />";
                var files = helper.GenerateCodeBehind(context, new List<string> { xaml }, schema, CodeGenLanguage.CppWinRT);
                string module = files.Single(file => file.FileName.EndsWith(".ixx")).Contents;
                StringAssert.Contains(module, "export module " + CppWinRTProjectionDependency.GetXamlClassModuleName("Project", "DifferentRoot.Empty" + element) + ";");
                StringAssert.Contains(module, "export import winrt.Microsoft.UI.Xaml;");
                StringAssert.Contains(module, "export import winrt.Windows.Foundation;");
            }
        }

        [TestMethod]
        public void Aggregator_OnlyReExportsIndependentInterfacesFromTheFullClassSet()
        {
            string text = CppWinRTProjectionDependency.WriteAggregator("Test", new[] { "Test.SecondPage", "Test.App", "Test.MainPage", "Test.MainPage" });
            Assert.IsFalse(text.Contains("Application_Xaml.Support"));
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
        public void ModuleBuild_MovesXamlDeclarationsOutOfTheLegacyHeaderContract()
        {
            var traditional = GeneratePage(false);
            var modules = GeneratePage(true);
            Assert.AreEqual(1, traditional.Count);
            Assert.AreEqual(2, modules.Count);

            string traditionalHeader = traditional.Single().Contents;
            StringAssert.Contains(traditionalHeader, "struct MainPageT");

            string sentinel = modules.Single(file => file.FileName.EndsWith(".h")).Contents;
            StringAssert.Contains(sentinel, "named-module sentinel");
            Assert.IsFalse(sentinel.Contains("struct MainPageT"));
            Assert.IsFalse(sentinel.Contains("#include <winrt/"));

            string module = modules.Single(file => file.FileName.EndsWith(".ixx")).Contents;
            StringAssert.Contains(module, "export module Test.Application_Xaml.MainPage;");
            StringAssert.Contains(module, "#define WINRT_IMPORT_MODULE");
            StringAssert.Contains(module, "#include \"MainPage.g.h\"");
            StringAssert.Contains(module, "#define XAML_IMPL_MODULE");
            StringAssert.Contains(module, "struct MainPageT");
            StringAssert.Contains(module, "export import winrt.Microsoft.UI.Xaml.Controls;");
            Assert.IsFalse(module.Contains("WINRT_XAML"));
            Assert.IsFalse(module.Contains("XAML_USE_MODULE"));
        }

        [TestMethod]
        public void App_ModuleOwnsTheGeneratedAppTemplate()
        {
            var files = GeneratePage(true, true);
            string sentinel = files.Single(file => file.FileName.EndsWith(".h")).Contents;
            Assert.IsFalse(sentinel.Contains("XamlAppMetadataProvider<D>::type"));

            string module = files.Single(file => file.FileName.EndsWith(".ixx")).Contents;
            StringAssert.Contains(module, "XamlAppMetadataProvider<D>::type");
            StringAssert.Contains(module, "winrt::make_self<XamlMetaDataProvider>()");
            Assert.IsFalse(module.Contains("AppT();"));
            Assert.IsFalse(module.Contains("~AppT();"));
        }

        [TestMethod]
        public void TypeInfoConsumer_SelectsHeadersOrModulesDuringGeneration()
        {
            var helper = new TestHelper();
            var project = new XamlProjectInfo
            {
                RootNamespace = "Test", ProjectName = "Test", TargetPlatformMinVersion = new Version(KnownVersions.Latest),
                ClassToHeaderFileMap = new Dictionary<string, string> { { "Test.MainPage", "MainPage.xaml.h" }, { "Test.SecondPage", "SecondPage.xaml.h" } }
            };
            project.SetEmptyAdditionalXamlTypeInfoIncludes();
            var schema = new XamlSchemaCodeInfo();

            string headerText = helper.GenerateTypeInfo(false, schema, project, new ClassName("Test.App"), CodeGenLanguage.CppWinRT)
                .Single(file => file.FileName == "XamlTypeInfo.g.cpp").Contents;
            StringAssert.Contains(headerText, "#include <vector>");
            Assert.IsFalse(headerText.Contains("import winrt."));
            Assert.IsFalse(headerText.Contains("import Test.Application_Xaml;"));
            Assert.IsFalse(headerText.Contains("XAML_USE_MODULE"));

            project.BuildXamlModules = true;
            string moduleText = helper.GenerateTypeInfo(false, schema, project, new ClassName("Test.App"), CodeGenLanguage.CppWinRT)
                .Single(file => file.FileName == "XamlTypeInfo.g.cpp").Contents;
            int firstImport = moduleText.IndexOf("import winrt.", StringComparison.Ordinal);
            int rootImport = moduleText.IndexOf("import Test.Application_Xaml;", StringComparison.Ordinal);
            Assert.IsTrue(firstImport >= 0);
            Assert.IsTrue(rootImport > firstImport);
            StringAssert.Contains(moduleText, "import Test.Application_Xaml.TypeInfo;");
            StringAssert.Contains(moduleText, "import Test.Application_Xaml.BindingInfo;");
            Assert.IsFalse(moduleText.Contains("Application_Xaml.Support"));
            foreach (string header in new[] { "MainPage.xaml.h", "SecondPage.xaml.h" })
            {
                int local = moduleText.IndexOf("#include \"" + header + "\"", StringComparison.Ordinal);
                Assert.IsTrue(local > rootImport);
            }
            StringAssert.Contains(moduleText, "#define WINRT_IMPORT_MODULE");
            StringAssert.Contains(moduleText, "import std;");
            Assert.IsFalse(moduleText.Contains("#include <vector>"));
            Assert.IsFalse(moduleText.Contains("module Test.Application_Xaml.TypeInfo;"));
            Assert.IsFalse(moduleText.Contains("XAML_USE_MODULE"));
            Assert.IsFalse(moduleText.Contains("WINRT_IMPORT_MODULE"));
            Assert.IsFalse(moduleText.Contains("export module"));
            Assert.AreNotEqual(headerText, moduleText);

            project.XamlCodeBehindModule = "Test.UserXaml";
            string authoredModuleText = helper.GenerateTypeInfo(false, schema, project, new ClassName("Test.App"), CodeGenLanguage.CppWinRT)
                .Single(file => file.FileName == "XamlTypeInfo.g.cpp").Contents;
            StringAssert.Contains(authoredModuleText, "import Test.UserXaml;");
            Assert.IsFalse(authoredModuleText.Contains("#include \"MainPage.xaml.h\""));
            Assert.IsFalse(authoredModuleText.Contains("#include \"SecondPage.xaml.h\""));
            project.XamlCodeBehindModule = null;

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
                    Assert.IsFalse(source.Contents.Contains("XAML_USE_MODULE"));
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
