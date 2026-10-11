// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License. See LICENSE in the project root for license information.

using Antlr4.Runtime;
using Antlr4.Runtime.Tree;
using Microsoft.UI.Xaml.Markup.Compiler.Parsing;
using Microsoft.UI.Xaml.Markup.Compiler.XamlDom;
using SuccinctCollectionSyntax;
using System;
using System.Collections.Generic;
using System.Text;
using System.Xaml;
using BailErrorStrategy = Microsoft.UI.Xaml.Markup.Compiler.Parsing.BailErrorStrategy;

namespace Microsoft.UI.Xaml.Markup.Compiler

{
    internal static class SuccinctSyntaxLexerExtensions
    {
        public static void ConfirmInputFullyConsumed(this SuccinctCollectionSyntaxLexer lexer)
        {
            if (!lexer.HitEOF)
            {
                var input = lexer.InputStream.ToString();
                var unconsumed = lexer.Token == null ? input : input.Substring(lexer.Token.StartIndex);
                throw new SuccinctCollectionSyntaxException(ErrorMessages.SyntaxError, unconsumed);
            }
        }
    }

    class SuccinctCollectionSyntaxVerifier
    {

        public static bool TryParse(string collectionItem, XamlDomNode locationForErrors, List<XamlCompileError> Errors, XamlMember property)
        {
            try
            {
                Parse(collectionItem);
            }
            catch (SuccinctCollectionSyntaxException e)
            {

                // locationforErrors only contains start of XAML property assignment, in order to find the position in markup it must be combined with the Antlr Line info from the exception object
                
                
                int markupLine = locationForErrors.StartLineNumber;
                int exceptionLine = e.Line;
                int row = markupLine + exceptionLine - 1;

                int markupColumn = locationForErrors.EndLinePosition;
                int exceptionColumn = e.Col;
                int column = markupColumn + exceptionColumn;

                Errors.Add(new XamlSuccinctSyntaxError(row, column, e.OffendingToken, locationForErrors.SourceFilePath));

                return false;
            }
            catch (Exception)
            {
                Errors.Add(new XamlValidationErrorCannotAssignTextToProperty(locationForErrors, property, collectionItem));
                return false;
            }
            return true;
        }

        private static string TrimItemWhitespace(string input)
        {
            var result = new StringBuilder(input.Length);
            int itemStart = 0;
            char quote = '\0';
            bool escaped = false;

            for (int i = 0; i < input.Length; i++)
            {
                char current = input[i];

                if (escaped)
                {
                    escaped = false;
                    continue;
                }

                if (current == '\\')
                {
                    escaped = true;
                    continue;
                }

                if (quote != '\0')
                {
                    if (current == quote)
                    {
                        quote = '\0';
                    }
                    continue;
                }

                if (current == '\'' || current == '"')
                {
                    quote = current;
                }
                else if (current == ',')
                {
                    result.Append(input.Substring(itemStart, i - itemStart).Trim());
                    result.Append(current);
                    itemStart = i + 1;
                }
            }

            result.Append(input.Substring(itemStart).Trim());
            return result.ToString();
        }

        public static void Parse(string bindPath)
        {
            // Whitespace surrounding collection items is insignificant.  Remove it before
            // parsing so quoted items after a comma are not mistaken for whitespace-only
            // unquoted items by the generated grammar.
            bindPath = TrimItemWhitespace(bindPath);

            // Antlr parsing engine setup
            var input = new AntlrInputStream(bindPath);
            var lexer = new SuccinctCollectionSyntaxLexer(input);
            var tokens = new CommonTokenStream(lexer);
            var parser = new SuccinctCollectionSyntaxParser(tokens);

            // redirect parsing errors as VS exceptions instead of console output
            // and disable the automatic error recovery handler
            parser.RemoveErrorListeners();
            parser.AddErrorListener(new SuccinctCollectionSyntaxErrorListener());
            parser.ErrorHandler = new BailErrorStrategy();

            // set our custom callback override to build up the SuccinctSyntax during parse
            var listener = new SuccinctCollectionSyntaxBaseListener();

            // Parse through EOF.  Parsing only items() can succeed after a valid prefix;
            // lexing ahead to EOF is not proof that every token was accepted by the parser.
            var walker = new ParseTreeWalker();

            walker.Walk(listener, parser.program());
        }
    }
}
