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
                var retList = new List<FileNameAndContentPair>();
                if (_isPass1)
                {
                    string legacyCompanionName = codeInfo.BaseFileName + _language.Pass1Extension;
                    retList.Add(new FileNameAndContentPair(
                        legacyCompanionName,
                        CppWinRTProjectionDependency.WriteXamlHeaderSentinel(_projectInfo.RootNamespace, codeInfo.ClassName.FullName)));

                    string implementationPartition = CppWinRTProjectionDependency.WriteClassImplementationPartition(
                        _projectInfo.RootNamespace,
                        codeInfo.ClassName.FullName,
                        model.DeclarationCppWinRTProjectionNamespaces,
                        codeInfo.BaseFileName + ".g.h",
                        code);
                    retList.Add(new FileNameAndContentPair(codeInfo.BaseFileName + ".xaml.g.ixx", implementationPartition));
                }
                else
                {
                    var partitions = new List<string>
                    {
                        CppWinRTProjectionDependency.GetCppWinRTImplementationPartitionName(_projectInfo.RootNamespace, codeInfo.ClassName.FullName),
                        CppWinRTProjectionDependency.GetAuthoredImplementationPartitionName(_projectInfo.RootNamespace, codeInfo.ClassName.FullName),
                    };
                    if (codeInfo.BindStatus != BindStatus.None)
                    {
                        partitions.Add("BindingInfo");
                    }
                    if (codeInfo.IsApplication && _projectInfo.ShouldGenerateTypeInfoCode)
                    {
                        partitions.Add("TypeInfo");
                    }

                    string implementationUnit = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                        _projectInfo.RootNamespace,
                        partitions,
                        model.NeededCppWinRTProjectionNamespaces) + "\n" + code;
                    retList.Add(new FileNameAndContentPair(codeInfo.BaseFileName + ".xaml.g.cpp", implementationUnit));
                }
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
                var retList = new List<FileNameAndContentPair>();
                if (_isPass1)
                {
                    string providerDeclarations = GenerateTypeInfoCode(_language.XamlMetaDataProviderPass1, appXamlInfo) ?? String.Empty;
                    string declarations =
                        "#define WINRT_IMPORT_MODULE\n"
                        + "#include \"XamlMetaDataProvider.g.h\"\n"
                        + "#undef WINRT_IMPORT_MODULE\n\n"
                        + code + Environment.NewLine + providerDeclarations;
                    var namespaces = CppWinRTProjectionDependency.TypeInfoSupportNamespaces;
                    if (!String.IsNullOrWhiteSpace(_projectInfo.RootNamespace))
                    {
                        namespaces = namespaces.Concat(new[] { _projectInfo.RootNamespace });
                    }
                    retList.Add(new FileNameAndContentPair(
                        "XamlTypeInfo.xaml.g.ixx",
                        CppWinRTProjectionDependency.WriteInternalPartition(_projectInfo.RootNamespace, "TypeInfo", namespaces, declarations)));

                    string libraryProvider = GenerateTypeInfoCode(_language.XamlMetaDataProviderPass2, appXamlInfo);
                    if (libraryProvider != null)
                    {
                        string preamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                            _projectInfo.RootNamespace,
                            new[] { "TypeInfo" },
                            CppWinRTProjectionDependency.TypeInfoSupportNamespaces);
                        retList.Add(new FileNameAndContentPair("XamlLibMetadataProvider.g.cpp", preamble + "\n" + libraryProvider));
                    }

                    string implementation = GenerateTypeInfoCode(_language.TypeInfoPass1ImplCodeGenerator, appXamlInfo);
                    if (implementation != null)
                    {
                        var implNamespaces = CppWinRTProjectionDependency.TypeInfoSupportNamespaces;
                        if (!String.IsNullOrWhiteSpace(_projectInfo.RootNamespace))
                        {
                            implNamespaces = implNamespaces.Concat(new[] { _projectInfo.RootNamespace });
                        }
                        string preamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                            _projectInfo.RootNamespace,
                            new[] { "TypeInfo" },
                            implNamespaces);
                        retList.Add(new FileNameAndContentPair("XamlTypeInfo.Impl.g.cpp", preamble + "\n" + implementation));
                    }
                }
                else
                {
                    var namespaces = CppWinRTProjectionDependency.TypeInfoSupportNamespaces;
                    if (!String.IsNullOrWhiteSpace(_projectInfo.RootNamespace))
                    {
                        namespaces = namespaces.Concat(new[] { _projectInfo.RootNamespace });
                    }
                    string preamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                        _projectInfo.RootNamespace,
                        new[] { "TypeInfo", "BindingInfo" },
                        namespaces);
                    retList.Add(new FileNameAndContentPair("XamlTypeInfo.g.cpp", preamble + "\n" + code));
                }
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
                if (_isPass1)
                {
                    return new List<FileNameAndContentPair>
                    {
                        new FileNameAndContentPair(
                            "XamlBindingInfo.xaml.g.ixx",
                            CppWinRTProjectionDependency.WriteInternalPartition(
                                _projectInfo.RootNamespace,
                                "BindingInfo",
                                CppWinRTProjectionDependency.BindingSupportNamespaces,
                                code))
                    };
                }

                string preamble = CppWinRTProjectionDependency.WriteImplementationUnitPreamble(
                    _projectInfo.RootNamespace,
                    new[] { "BindingInfo" },
                    CppWinRTProjectionDependency.BindingSupportNamespaces);
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
