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

        public static string GetXamlPrimaryModuleName(string rootNamespace)
        {
            return string.IsNullOrWhiteSpace(rootNamespace)
                ? "Application_Xaml"
                : $"{rootNamespace}.Application_Xaml";
        }

        public static string GetXamlClassModuleName(string rootNamespace, string runtimeClassName)
        {
            // Escape uppercase/underscore/non-ASCII characters so module identities stay
            // distinct even when their IFC filenames live on a case-insensitive filesystem.
            var segments = runtimeClassName.Replace("::", ".").Split('.').Select(segment =>
                "C_" + String.Concat(segment.Select(character =>
                    character >= 'a' && character <= 'z' || character >= '0' && character <= '9'
                        ? character.ToString()
                        : "_" + ((int)character).ToString("x4", System.Globalization.CultureInfo.InvariantCulture))));
            return $"{GetXamlPrimaryModuleName(rootNamespace)}.Class.{String.Join(".", segments)}";
        }

        public static IEnumerable<string> BindingSupportNamespaces => new[]
        {
            KnownNamespaces.WindowsFoundation, KnownNamespaces.WindowsFoundationCollections,
            KnownNamespaces.Xaml, KnownNamespaces.XamlControls, KnownNamespaces.XamlData,
            KnownNamespaces.XamlMarkup, KnownNamespaces.XamlInterop
        };

        public static IEnumerable<string> TypeInfoSupportNamespaces => new[]
        {
            KnownNamespaces.WindowsFoundation, KnownNamespaces.XamlMarkup, KnownNamespaces.WindowsXamlInterop
        };

        public static string WriteInterface(string moduleName, IEnumerable<string> namespaces,
            IEnumerable<string> headers, string supportModule = null)
        {
            var text = new StringBuilder();
            text.AppendLine("// Generated XAML declaration module.");
            text.AppendLine("module;");
            text.AppendLine("#include <unknwn.h>");
            text.AppendLine("#include <winrt/base_macros.h>");
            text.AppendLine("#undef GetCurrentTime");
            text.AppendLine($"export module {moduleName};");
            text.AppendLine("import std;");
            foreach (var ns in namespaces.Distinct(StringComparer.Ordinal).OrderBy(ns => ns, StringComparer.Ordinal))
            {
                text.AppendLine($"export import {GetModuleName(ns)};");
            }
            if (supportModule != null)
            {
                text.AppendLine($"export import {supportModule};");
            }
            text.AppendLine("#define XAML_IMPL_MODULE");
            foreach (var header in headers)
            {
                text.AppendLine($"#include \"{header}\"");
            }
            text.AppendLine("#undef XAML_IMPL_MODULE");
            return text.ToString();
        }

        public static string WriteAggregator(string rootNamespace, IEnumerable<string> classNames)
        {
            string moduleName = GetXamlPrimaryModuleName(rootNamespace);
            var text = new StringBuilder();
            text.AppendLine("// Generated project XAML module. Declarations belong to the individual interfaces.");
            text.AppendLine($"export module {moduleName};");
            text.AppendLine($"export import {moduleName}.Support;");
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
            string directive = $"#if defined(XAML_USE_MODULE) || defined(WINRT_IMPORT_MODULE)\nimport {CppWinRTProjectionDependency.GetModuleName(projectionNamespace)};\n#else\n#include <{header}>\n#endif";
            return optionalHeader ? $"#if __has_include(<{header}>)\n{directive}\n#endif" : directive;
        }

        public string GetCppWinRTConsumerPreamble()
        {
            // Generated consumers own their native preamble; no application /FI is needed.
            return "#ifdef XAML_USE_MODULE\n#include <windows.h>\n#include <unknwn.h>\n#include <algorithm>\n#include <cstddef>\n#include <cstdint>\n#include <functional>\n#include <map>\n#include <memory>\n#include <mutex>\n#include <regex>\n#include <string>\n#include <type_traits>\n#include <utility>\n#include <vector>\n#include <winrt/base_macros.h>\n#undef GetCurrentTime\n#ifndef WINRT_IMPORT_MODULE\n#define WINRT_IMPORT_MODULE\n#endif\n#endif";
        }

        public static String Projection(string typeName)
        {
            string newName = Globalize(typeName);

            // The check of "::winrt::" instead of "::winrt" is deliberate here - otherwise user-defined types from a namespace starting
            // with "winrt" could be confused as already having the "::winrt" prefix (e.g. a "winrt_UserNamespace::UserType" that we want to convert to "::winrt::winrt_UserNamespace::UserType").
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
