// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License. See LICENSE in the project root for license information.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Xaml;

namespace Microsoft.UI.Xaml.Markup.Compiler.CodeGen
{
    internal class XamlCodeGenerator
    {
        private Language _language;
        private bool _isPass1;
        XamlProjectInfo _projectInfo;
        XamlSchemaCodeInfo _schemaInfo;

        internal bool? GenerateTypeInfoOverride { get; set; }

        public XamlCodeGenerator(Language language, bool isPass1, XamlProjectInfo projectInfo, XamlSchemaCodeInfo schemaInfo)
        {
            _language = language;
            _isPass1 = isPass1;
            _projectInfo = projectInfo;
            _schemaInfo = schemaInfo;
        }

        private static string KeepFrom(string code, string marker)
        {
            int index = code.IndexOf(marker, StringComparison.Ordinal);
            if (index < 0)
            {
                throw new InvalidOperationException("Expected generated C++ marker was not found: " + marker);
            }
            return code.Substring(index);
        }

        public List<FileNameAndContentPair> GenerateCodeBehind(XamlClassCodeInfo codeInfo, out IEnumerable<FileNameAndChecksumPair> xamlFilesChecksumPairs)
        {
            CodeGeneratorDelegate codeGenDelegate;
            T4Base codeGenerator;
            xamlFilesChecksumPairs = null;
            if (codeInfo.IsApplication)
            {
                codeGenDelegate = _isPass1 ? _language.AppPass1CodeGenerator : _language.AppPass2CodeGenerator;
            }
            else
            {
                codeGenDelegate = _isPass1 ? _language.PagePass1CodeGenerator : _language.PagePass2CodeGenerator;
            }
            if (codeGenDelegate == null)
            {
                return null;
            }

            codeGenerator = codeGenDelegate();
            var model = new PageDefinition(_projectInfo, _schemaInfo) { CodeInfo = codeInfo };
            codeGenerator.SetModel(_projectInfo, _schemaInfo, model);

            string code = codeGenerator.TransformText();
            xamlFilesChecksumPairs = model.XamlFileFullPathAndCheckSums;
            Debug.Assert(!String.IsNullOrEmpty(codeInfo.BaseFileName));

            if (_language.Name == ProgrammingLanguage.CppWinRT && _projectInfo.BuildXamlModules)
            {
                string moduleName = CppWinRTProjectionDependency.GetXamlClassModuleName(_projectInfo.RootNamespace, codeInfo.ClassName.FullName);
                var retList = new List<FileNameAndContentPair>();

                if (_isPass1)
                {
                    // C++/WinRT probes for <Type>.xaml.g.h before emitting its legacy TypeT = Type_base
                    // fallback. Keep that physical probe file, but move every XamlC declaration into the BMI.
                    retList.Add(new FileNameAndContentPair(
                        codeInfo.BaseFileName + _language.Pass1Extension,
                        CppWinRTProjectionDependency.WriteXamlHeaderSentinel(moduleName)));

                    IEnumerable<string> projectionNamespaces = model.DeclarationCppWinRTProjectionNamespaces;
                    // A C++/WinRT producer <Type>.g.h defines <Type>_base in terms of the
                    // runtimeclass projection that owns x:Class. Import that exact namespace,
                    // not the project root: nested namespaces can have their own projection
                    // modules and a bare winrt.<RootNamespace> module need not exist.
                    if (!codeInfo.IsApplication && !String.IsNullOrWhiteSpace(codeInfo.ClassName.Namespace))
                    {
                        projectionNamespaces = projectionNamespaces.Concat(new[] { codeInfo.ClassName.Namespace });
                    }

                    retList.Add(new FileNameAndContentPair(
                        codeInfo.BaseFileName + ".xaml.g.ixx",
                        CppWinRTProjectionDependency.WriteSourceInterface(
                            moduleName,
                            projectionNamespaces,
                            code,
                            importedModules: codeInfo.IsApplication && _projectInfo.ShouldGenerateTypeInfoCode
                                ? new[] { CppWinRTProjectionDependency.GetTypeInfoModuleName(_projectInfo.RootNamespace) }
                                : null,
                            // cppwinrt names the producer scaffold after the runtimeclass, not the
                            // XAML item. These names can differ (for example DummyFile.xaml can
                            // declare Test.MainPage), so derive <Type>.g.h from x:Class.
                            cppWinRTProducerHeader: codeInfo.IsApplication ? null : codeInfo.ClassName.ShortName + ".g.h")));
                    return retList;
                }

                // The T4 body still contains the legacy preamble so header builds remain unchanged.
                // Module builds own the TU preamble here and keep only the implementation body.
                code = KeepFrom(code, codeInfo.IsApplication ? "#if defined _DEBUG" : "#pragma warning(push)");

                var importedModules = new List<string>
                {
                    moduleName,
                };
                if (codeInfo.BindStatus != BindStatus.None)
                {
                    importedModules.Add(CppWinRTProjectionDependency.GetBindingInfoModuleName(_projectInfo.RootNamespace));
                }
                if (codeInfo.IsApplication && _projectInfo.ShouldGenerateTypeInfoCode)
                {
                    importedModules.Add(CppWinRTProjectionDependency.GetTypeInfoModuleName(_projectInfo.RootNamespace));
                }

                string preamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                    moduleName,
                    model.NeededCppWinRTProjectionNamespaces,
                    importedModules);
                string localHeaders = String.Join(
                    Environment.NewLine,
                    model.NeededLocalXamlHeaderFiles.Select(header => "#include \"" + header + "\""));
                retList.Add(new FileNameAndContentPair(
                    codeInfo.BaseFileName + ".xaml.g.cpp",
                    preamble + "\n" + localHeaders + "\n" + code));
                return retList;
            }

            string codeFileName = codeInfo.BaseFileName + (_isPass1 ? _language.Pass1Extension : _language.Pass2Extension);
            return new List<FileNameAndContentPair> { new FileNameAndContentPair(codeFileName, code) };
        }

        public List<FileNameAndContentPair> GenerateTypeInfo(ClassName appXamlInfo)
        {
            CodeGeneratorDelegate codeGenDelegate = _isPass1 ? _language.TypeInfoPass1CodeGenerator : _language.TypeInfoPass2CodeGenerator;
            string code = GenerateTypeInfoCode(codeGenDelegate, appXamlInfo);
            if (code == null)
            {
                return null;
            }

            if (_language.Name == ProgrammingLanguage.CppWinRT && _projectInfo.BuildXamlModules)
            {
                string moduleName = CppWinRTProjectionDependency.GetTypeInfoModuleName(_projectInfo.RootNamespace);
                var retList = new List<FileNameAndContentPair>();
                var projectionNamespaces = CppWinRTProjectionDependency.TypeInfoSupportNamespaces.ToList();
                if (!String.IsNullOrWhiteSpace(_projectInfo.RootNamespace))
                {
                    projectionNamespaces.Add(_projectInfo.RootNamespace);
                }

                if (_isPass1)
                {
                    string providerDeclarations = GenerateTypeInfoCode(_language.XamlMetaDataProviderPass1, appXamlInfo) ?? String.Empty;
                    string declarations = code + Environment.NewLine + providerDeclarations;
                    retList.Add(new FileNameAndContentPair(
                        "XamlTypeInfo.xaml.g.ixx",
                        CppWinRTProjectionDependency.WriteSourceInterface(
                            moduleName,
                            projectionNamespaces,
                            declarations,
                            cppWinRTProducerHeader: "XamlMetaDataProvider.g.h",
                            exportProjectionDependencies: false)));

                    string libraryProvider = GenerateTypeInfoCode(_language.XamlMetaDataProviderPass2, appXamlInfo);
                    if (!String.IsNullOrWhiteSpace(libraryProvider))
                    {
                        string body = libraryProvider.Contains("namespace winrt::")
                            ? KeepFrom(libraryProvider, "namespace winrt::")
                            : libraryProvider;
                        string preamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                            moduleName,
                            projectionNamespaces,
                            new[] { moduleName });
                        retList.Add(new FileNameAndContentPair("XamlLibMetadataProvider.g.cpp", preamble + "\n" + body));
                    }

                    string implementation = GenerateTypeInfoCode(_language.TypeInfoPass1ImplCodeGenerator, appXamlInfo);
                    if (!String.IsNullOrWhiteSpace(implementation))
                    {
                        implementation = KeepFrom(implementation, "namespace winrt::");
                        string preamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                            moduleName,
                            projectionNamespaces,
                            new[] { moduleName });
                        retList.Add(new FileNameAndContentPair("XamlTypeInfo.Impl.g.cpp", preamble + "\n" + implementation));
                    }
                    return retList;
                }

                code = KeepFrom(code, "namespace winrt::");
                var importedModules = new List<string>
                {
                    moduleName,
                    CppWinRTProjectionDependency.GetBindingInfoModuleName(_projectInfo.RootNamespace),
                    CppWinRTProjectionDependency.GetXamlPrimaryModuleName(_projectInfo.RootNamespace),
                };
                string typeInfoPreamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                    moduleName,
                    projectionNamespaces,
                    importedModules);
                string localHeaders = ! _projectInfo.GenerateIncrementalTypeInfo && _projectInfo.ClassToHeaderFileMap != null
                    ? String.Join(Environment.NewLine, _projectInfo.ClassToHeaderFileMap.Values.Distinct(StringComparer.Ordinal).Select(header => "#include \"" + header + "\""))
                    : String.Empty;
                retList.Add(new FileNameAndContentPair("XamlTypeInfo.g.cpp", typeInfoPreamble + "\n" + localHeaders + "\n" + code));
                return retList;
            }

            var legacy = new List<FileNameAndContentPair>();
            string extension = _isPass1 && _language.Name != ProgrammingLanguage.CSharp ? _language.Pass1Extension : _language.Pass2Extension;
            string fileName = "XamlTypeInfo" + extension;
            if (!_isPass1 && fileName.EndsWith(".g.hpp"))
            {
                fileName = "XamlTypeInfo.g.cpp";
            }
            legacy.Add(new FileNameAndContentPair(fileName, code));

            if (_isPass1)
            {
                code = GenerateTypeInfoCode(_language.XamlMetaDataProviderPass1, appXamlInfo);
                if (code != null)
                {
                    legacy.Add(new FileNameAndContentPair("XamlMetaDataProvider.h", code));
                }
                code = GenerateTypeInfoCode(_language.XamlMetaDataProviderPass2, appXamlInfo);
                if (code != null)
                {
                    legacy.Add(new FileNameAndContentPair("XamlLibMetadataProvider.g.cpp", code));
                }
                code = GenerateTypeInfoCode(_language.TypeInfoPass1ImplCodeGenerator, appXamlInfo);
                if (code != null)
                {
                    legacy.Add(new FileNameAndContentPair("XamlTypeInfo.Impl.g.cpp", code));
                }
            }
            return legacy;
        }

        public List<FileNameAndContentPair> GenerateBindingInfo(
            Dictionary<string, XamlType> observableVectorTypes,
            Dictionary<string, XamlType> observableMapTypes,
            Dictionary<string, XamlMember> bindingSetters,
            bool eventBindingUsed)
        {
            Debug.Assert(_language.IsNative, "Binding infos are only supposed to be generated for native");
            T4Base codeGenerator = _isPass1 ? _language.BindingInfoPass1CodeGenerator() : _language.BindingInfoPass2CodeGenerator();
            codeGenerator.SetModel(
                _projectInfo,
                _schemaInfo,
                new BindingInfoDefinition(_projectInfo, _schemaInfo)
                {
                    ObservableVectorTypes = observableVectorTypes,
                    ObservableMapTypes = observableMapTypes,
                    BindingSetters = bindingSetters,
                    EventBindingUsed = eventBindingUsed,
                });

            string code = codeGenerator.TransformText();
            Debug.Assert(code != null);
            if (code == null)
            {
                return new List<FileNameAndContentPair>();
            }

            if (_language.Name == ProgrammingLanguage.CppWinRT && _projectInfo.BuildXamlModules)
            {
                string moduleName = CppWinRTProjectionDependency.GetBindingInfoModuleName(_projectInfo.RootNamespace);
                if (_isPass1)
                {
                    return new List<FileNameAndContentPair>
                    {
                        new FileNameAndContentPair(
                            "XamlBindingInfo.xaml.g.ixx",
                            CppWinRTProjectionDependency.WriteSourceInterface(
                                moduleName,
                                CppWinRTProjectionDependency.BindingSupportNamespaces,
                                code,
                                exportProjectionDependencies: false))
                    };
                }

                code = KeepFrom(code, "namespace winrt::");
                string preamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                    moduleName,
                    CppWinRTProjectionDependency.BindingSupportNamespaces,
                    new[] { moduleName });
                return new List<FileNameAndContentPair>
                {
                    new FileNameAndContentPair("XamlBindingInfo.xaml.g.cpp", preamble + "\n" + code)
                };
            }

            string filename = KnownStrings.XamlBindingInfo + (_isPass1 ? _language.Pass1Extension : _language.Pass2Extension);
            return new List<FileNameAndContentPair> { new FileNameAndContentPair(filename, code) };
        }

        string GenerateTypeInfoCode(CodeGeneratorDelegate codeGenDelegate, ClassName appXamlInfo)
        {
            if (codeGenDelegate == null)
            {
                return null;
            }
            T4Base codeGenerator = codeGenDelegate();
            codeGenerator.SetModel(_projectInfo, _schemaInfo,
                new TypeInfoDefinition(_projectInfo, _schemaInfo)
                {
                    AppXamlInfo = appXamlInfo,
                    IsPass1 = _isPass1,
                    GenerateTypeInfoOverride = GenerateTypeInfoOverride
                });
            return codeGenerator.TransformText();
        }
    }
}
