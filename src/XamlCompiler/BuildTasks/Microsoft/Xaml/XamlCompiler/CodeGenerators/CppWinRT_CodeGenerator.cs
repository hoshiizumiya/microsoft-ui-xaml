// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License. See LICENSE in the project root for license information.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Xaml;

namespace Microsoft.UI.Xaml.Markup.Compiler.CodeGen
{
    internal static class CppWinRTProjectionDependency
    {
        private const string EscapedModuleSegmentPrefix = "__XamlEscaped_";

        public static string GetNamespace(Type type)
        {
            Type adjustedType = type;
            while (adjustedType != null && adjustedType.IsArray)
            {
                adjustedType = adjustedType.GetElementType();
            }

            if (adjustedType == null || XamlSchemaCodeInfo.IsProjectedPrimitiveCppType(adjustedType.FullName))
            {
                return null;
            }

            return adjustedType.Namespace;
        }

        public static IEnumerable<string> GetNamespaces(Type type)
        {
            Type adjustedType = type;
            while (adjustedType != null && adjustedType.IsArray)
            {
                adjustedType = adjustedType.GetElementType();
            }
            string projectionNamespace = GetNamespace(adjustedType);

            if (projectionNamespace == null)
            {
                yield break;
            }

            yield return projectionNamespace;

            if (adjustedType.IsGenericType)
            {
                foreach (var genericArgument in adjustedType.GetGenericArguments())
                {
                    foreach (var nestedNamespace in GetNamespaces(genericArgument))
                    {
                        yield return nestedNamespace;
                    }
                }
            }
        }

        public static IEnumerable<string> GetNamespaces(Type type, string unresolvedNamespace)
        {
            if (type == null)
            {
                if (!String.IsNullOrWhiteSpace(unresolvedNamespace))
                {
                    yield return unresolvedNamespace;
                }
                yield break;
            }

            foreach (var projectionNamespace in GetNamespaces(type))
            {
                yield return projectionNamespace;
            }
        }

        public static string GetHeaderFile(string projectionNamespace)
        {
            return $"winrt/{projectionNamespace}.h";
        }

        public static string GetModuleName(string projectionNamespace)
        {
            return $"winrt.{projectionNamespace}";
        }

        private static string EncodeModuleSegment(string segment)
        {
            if (IsModuleIdentifier(segment) && !segment.StartsWith(EscapedModuleSegmentPrefix, StringComparison.Ordinal))
            {
                return segment;
            }

            return EscapedModuleSegmentPrefix + String.Concat(segment.Select(character =>
                ((int)character).ToString("x4", System.Globalization.CultureInfo.InvariantCulture)));
        }

        private static bool IsModuleIdentifier(string value)
        {
            if (String.IsNullOrEmpty(value) || !(value[0] == '_' || Char.IsLetter(value[0])))
            {
                return false;
            }

            foreach (char character in value.Skip(1))
            {
                var category = Char.GetUnicodeCategory(character);
                if (character != '_' && !Char.IsLetterOrDigit(character) &&
                    category != System.Globalization.UnicodeCategory.NonSpacingMark &&
                    category != System.Globalization.UnicodeCategory.SpacingCombiningMark)
                {
                    return false;
                }
            }

            const string keywords = " alignas alignof and and_eq asm auto bitand bitor bool break case catch char char8_t char16_t char32_t class compl concept const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do double dynamic_cast else enum explicit export extern false float for friend goto if inline int long module import mutable namespace new noexcept not not_eq nullptr operator or or_eq private protected public register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typeid typename union unsigned using virtual void volatile wchar_t while xor xor_eq ";
            return keywords.IndexOf(" " + value + " ", StringComparison.Ordinal) < 0;
        }

        private static string EncodeQualifiedName(string qualifiedName)
        {
            if (String.IsNullOrWhiteSpace(qualifiedName))
            {
                throw new ArgumentException("A qualified name is required.", nameof(qualifiedName));
            }

            return String.Join(".", qualifiedName.Replace("::", ".").Split('.').Select(EncodeModuleSegment));
        }

        public static string GetXamlPrimaryModuleName(string rootNamespace)
        {
            if (String.IsNullOrWhiteSpace(rootNamespace))
            {
                return "Application_Xaml";
            }

            string moduleRoot = rootNamespace.Split('.').All(IsModuleIdentifier)
                ? rootNamespace
                : "XamlProject." + EncodeModuleSegment(rootNamespace);
            return moduleRoot + ".Application_Xaml";
        }

        public static string GetXamlClassModuleName(string rootNamespace, string runtimeClassName)
        {
            if (String.IsNullOrWhiteSpace(runtimeClassName))
            {
                throw new ArgumentException("A harvested x:Class runtime name is required.", nameof(runtimeClassName));
            }

            string normalizedRuntimeName = runtimeClassName.Replace("::", ".");
            string normalizedRoot = rootNamespace?.Replace("::", ".");
            if (!String.IsNullOrWhiteSpace(normalizedRoot) && normalizedRuntimeName.StartsWith(normalizedRoot + ".", StringComparison.Ordinal))
            {
                normalizedRuntimeName = normalizedRuntimeName.Substring(normalizedRoot.Length + 1);
            }

            return $"{GetXamlPrimaryModuleName(rootNamespace)}.{EncodeQualifiedName(normalizedRuntimeName)}";
        }

        public static string GetAuthoredXamlModuleName(string runtimeClassName)
        {
            return EncodeQualifiedName(runtimeClassName);
        }

        public static string GetBindingInfoModuleName(string rootNamespace)
        {
            return GetXamlPrimaryModuleName(rootNamespace) + ".BindingInfo";
        }

        public static string GetTypeInfoModuleName(string rootNamespace)
        {
            return GetXamlPrimaryModuleName(rootNamespace) + ".TypeInfo";
        }

        public static IEnumerable<string> BindingSupportNamespaces => new[]
        {
            KnownNamespaces.WindowsFoundation,
            KnownNamespaces.WindowsFoundationCollections,
            KnownNamespaces.Xaml,
            KnownNamespaces.XamlControls,
            KnownNamespaces.XamlData,
            KnownNamespaces.XamlMarkup,
            KnownNamespaces.XamlInterop,
        };

        public static IEnumerable<string> TypeInfoSupportNamespaces => new[]
        {
            KnownNamespaces.WindowsFoundation,
            KnownNamespaces.XamlMarkup,
            KnownNamespaces.WindowsXamlInterop,
        };

        public static string WriteXamlHeaderSentinel(string moduleName)
        {
            return "#pragma once\n"
                + "// XamlC named-module sentinel.\n"
                + "// The real generated XAML declarations are owned by " + moduleName + ".\n"
                + "// C++/WinRT probes for this companion before generating its legacy TypeT = Type_base fallback.\n";
        }

        public static string WriteSourceInterface(
            string moduleName,
            IEnumerable<string> namespaces,
            string generatedSource,
            IEnumerable<string> importedModules = null,
            string cppWinRTProducerHeader = null,
            bool exportProjectionDependencies = true)
        {
            var text = new StringBuilder();
            text.AppendLine("// Generated XAML declaration module.");
            text.AppendLine("module;");
            text.AppendLine("#include <unknwn.h>");
            text.AppendLine("#include <winrt/base_macros.h>");
            text.AppendLine("#undef GetCurrentTime");
            text.AppendLine($"export module {moduleName};");
            text.AppendLine("import std;");
            text.AppendLine("import winrt_base;");

            foreach (var ns in namespaces.Where(ns => !String.IsNullOrWhiteSpace(ns)).Distinct(StringComparer.Ordinal).OrderBy(ns => ns, StringComparer.Ordinal))
            {
                text.AppendLine($"{(exportProjectionDependencies ? "export " : String.Empty)}import {GetModuleName(ns)};");
            }

            if (importedModules != null)
            {
                foreach (var importedModule in importedModules.Where(name => !String.IsNullOrWhiteSpace(name)).Distinct(StringComparer.Ordinal).OrderBy(name => name, StringComparer.Ordinal))
                {
                    text.AppendLine($"import {importedModule};");
                }
            }

            if (!String.IsNullOrWhiteSpace(cppWinRTProducerHeader))
            {
                text.AppendLine("#define WINRT_IMPORT_MODULE");
                text.AppendLine($"#include \"{cppWinRTProducerHeader}\"");
                text.AppendLine("#undef WINRT_IMPORT_MODULE");
            }

            text.AppendLine("#define XAML_IMPL_MODULE");
            text.AppendLine(generatedSource);
            text.AppendLine("#undef XAML_IMPL_MODULE");
            return text.ToString();
        }

        public static string WriteImplementationUnitPreamble(
            string moduleName,
            IEnumerable<string> projectionNamespaces,
            IEnumerable<string> importedModules = null)
        {
            var text = new StringBuilder();
            text.AppendLine("#include <windows.h>");
            text.AppendLine("#include <unknwn.h>");
            text.AppendLine("#include <winrt/base_macros.h>");
            text.AppendLine("#include <algorithm>");
            text.AppendLine("#include <cstddef>");
            text.AppendLine("#include <cstdint>");
            text.AppendLine("#include <functional>");
            text.AppendLine("#include <list>");
            text.AppendLine("#include <map>");
            text.AppendLine("#include <memory>");
            text.AppendLine("#include <mutex>");
            text.AppendLine("#include <regex>");
            text.AppendLine("#include <string>");
            text.AppendLine("#include <type_traits>");
            text.AppendLine("#include <unordered_map>");
            text.AppendLine("#include <utility>");
            text.AppendLine("#include <vector>");
            text.AppendLine("#undef GetCurrentTime");
            // C++/WinRT 3.x implementation mode uses an ordinary translation unit.
            // The standard library is owned textually here, before any imports; only
            // C++/WinRT and XamlC named modules are imported below.
            text.AppendLine("#ifndef WINRT_IMPORT_MODULE");
            text.AppendLine("#define WINRT_IMPORT_MODULE");
            text.AppendLine("#endif");
            text.AppendLine("import winrt_base;");

            if (importedModules != null)
            {
                foreach (var importedModule in importedModules.Where(name => !String.IsNullOrWhiteSpace(name)).Distinct(StringComparer.Ordinal).OrderBy(name => name, StringComparer.Ordinal))
                {
                    text.AppendLine($"import {importedModule};");
                }
            }

            foreach (var ns in projectionNamespaces.Where(ns => !String.IsNullOrWhiteSpace(ns)).Distinct(StringComparer.Ordinal).OrderBy(ns => ns, StringComparer.Ordinal))
            {
                text.AppendLine($"import {GetModuleName(ns)};");
            }
            return text.ToString();
        }

        public static string WriteAggregator(string rootNamespace, IEnumerable<string> classNames)
        {
            string moduleName = GetXamlPrimaryModuleName(rootNamespace);
            var text = new StringBuilder();
            text.AppendLine("// Generated project XAML module. Declarations belong to the individual interfaces.");
            text.AppendLine($"export module {moduleName};");
            foreach (var name in classNames.Distinct(StringComparer.Ordinal).OrderBy(name => name, StringComparer.Ordinal))
            {
                text.AppendLine($"export import {GetXamlClassModuleName(rootNamespace, name)};");
            }
            return text.ToString();
        }
    }

    internal class CppWinRT_CodeGenerator<T> : NativeCodeGenerator<T>
    {
        public override string ToStringWithCulture(ICodeGenOutput codegenOutput)
        {
            return codegenOutput.CppWinRTName();
        }

        public override string ToStringWithCulture(XamlType type)
        {
            return type.CppWinRTName();
        }

        public string GetCppWinRTProjectionDependencyDirective(string projectionNamespace, bool optionalHeader = false)
        {
            string header = CppWinRTProjectionDependency.GetHeaderFile(projectionNamespace);
            string directive = ProjectInfo.BuildXamlModules
                ? $"import {CppWinRTProjectionDependency.GetModuleName(projectionNamespace)};"
                : $"#include <{header}>";
            return optionalHeader ? $"#if __has_include(<{header}>)\n{directive}\n#endif" : directive;
        }

        public string GetCppWinRTProjectionHeaderDirective(string projectionNamespace, bool optionalHeader = false)
        {
            string header = CppWinRTProjectionDependency.GetHeaderFile(projectionNamespace);
            string directive = $"#include <{header}>";
            return optionalHeader ? $"#if __has_include(<{header}>)\n{directive}\n#endif" : directive;
        }

        public string GetCppWinRTConsumerPreamble()
        {
            if (typeof(T) != typeof(TypeInfoDefinition) || !ProjectInfo.BuildXamlModules)
            {
                return String.Empty;
            }

            return "#include <windows.h>\n#include <unknwn.h>\n#include <winrt/base_macros.h>\n#undef GetCurrentTime";
        }

        public static String Projection(string typeName)
        {
            string newName = Globalize(typeName);

            if (!newName.StartsWith("::winrt::"))
            {
                newName = "::winrt" + newName;
            }
            else
            {
                throw new ArgumentException("Name should not already contain ::winrt prefix");
            }
            newName = newName.Replace("<::", "<::winrt::");
            newName = newName.Replace("::winrt::winrt::", "::winrt::");
            return newName;
        }

        protected string GetBindingTrackingClassName(BindUniverse bindUniverse, XamlClassCodeInfo codeInfo)
        {
            return Colonize(bindUniverse.NeedsCppBindingTrackingClass ?
                bindUniverse.BindingsTrackingClassName :
                Projection($"{ProjectInfo.RootNamespace}::implementation::XamlBindingTrackingBase"));
        }

        public IEnumerable<string> GetCacheDeclarations(BindUniverse bindUniverse)
        {
            foreach (var step in bindUniverse.BindPathSteps.Values.Where(step => step.IsIncludedInUpdate == true && step.NeedsUpdateChildListeners))
            {
                if (step.ImplementsINPC && step.RequiresChildNotification)
                {
                    if (step is RootStep)
                    {
                        yield return $"::winrt::weak_ref<{Projection(KnownNamespaces.XamlData)}::INotifyPropertyChanged> cachePC_{step.CodeName};";
                    }
                    else
                    {
                        yield return $"{Projection(KnownNamespaces.XamlData)}::INotifyPropertyChanged cachePC_{step.CodeName}{{nullptr}};";
                    }
                }
                if (step.ImplementsINDEI)
                {
                    yield return $"{Projection(KnownNamespaces.XamlData)}::INotifyDataErrorInfo cacheEC_{step.CodeName}{{nullptr}};";
                }
                if (step.ImplementsIObservableVector && step.RequiresChildNotification)
                {
                    yield return step.ValueType.CppWinRTName() + " cacheVC_" + step.CodeName + "{nullptr};";
                }
                if (step.ImplementsIObservableMap && step.RequiresChildNotification)
                {
                    yield return step.ValueType.CppWinRTName() + " cacheMC_" + step.CodeName + "{nullptr};";
                }
                else if (step.ImplementsINCC)
                {
                    yield return $"{Projection(KnownNamespaces.XamlInterop)}::INotifyCollectionChanged cacheCC_{step.CodeName}{{nullptr}};";
                }
                foreach (var child in step.TrackingSteps.OfType<DependencyPropertyStep>())
                {
                    if (step is RootStep)
                    {
                        yield return $"::winrt::weak_ref<{Projection(KnownNamespaces.Xaml)}::DependencyObject> cacheDPC_{child.CodeName};";
                    }
                    else
                    {
                        yield return $"{Projection(KnownNamespaces.Xaml)}::DependencyObject cacheDPC_{child.CodeName}{{nullptr}};";
                    }
                }
            }
        }

        public IEnumerable<string> GetTokenDeclarations(BindUniverse bindUniverse)
        {
            foreach (var step in bindUniverse.BindPathSteps.Values.Where(step => step.IsIncludedInUpdate == true && step.NeedsUpdateChildListeners))
            {
                if (step.ImplementsINPC)
                {
                    yield return $"::winrt::event_token tokenPC_{step.CodeName} {{}};";
                }
                if (step.ImplementsINDEI)
                {
                    yield return $"::winrt::event_token tokenEC_{step.CodeName} {{}};";
                }
                if (step.ImplementsIObservableVector)
                {
                    yield return $"::winrt::event_token tokenVC_{step.CodeName} {{}};";
                }
                if (step.ImplementsIObservableMap)
                {
                    yield return $"::winrt::event_token tokenMC_{step.CodeName} {{}};";
                }
                else if (step.ImplementsINCC)
                {
                    yield return $"::winrt::event_token tokenCC_{step.CodeName} {{}};";
                }
            }

            foreach (var step in bindUniverse.BindPathSteps.Values.Where(step => step.IsIncludedInUpdate == true && step.NeedsUpdateChildListeners))
            {
                foreach (var child in step.TrackingSteps.OfType<DependencyPropertyStep>())
                {
                    yield return $"std::int64_t tokenDPC_{child.CodeName}{{0}};";
                }
            }
        }
    }
}
