// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// The command bar's inline calculator: what it answers, what it refuses, and
/// how it writes the answer back in the person's own number format.
///
/// Expectations are the upstream suite's (Tests/CommandBarFeatureTests.swift,
/// "Command bar calculator"), run against the local `CommandBarMath`.
enum CommandBarMathCases {
    static func run(_ expect: CommandBarExpect) {
        func math(_ input: String, decimal: String = ".", grouping: String = ",") -> String? {
            CommandBarMath.evaluate(input,
                                    decimalSeparator: decimal,
                                    groupingSeparator: grouping,
                                    locale: Locale(identifier: "en_US"))?.formatted
        }
        func value(_ input: String, decimal: String = ".", grouping: String = ",") -> Double? {
            CommandBarMath.evaluate(input,
                                    decimalSeparator: decimal,
                                    groupingSeparator: grouping,
                                    locale: Locale(identifier: "en_US"))?.value
        }

        // MARK: Ordinary arithmetic

        expect(math("2+2") == "4", "the calculator answers a sum")
        expect(math("10 * 4.5") == "45", "spaces and decimals are fine")
        expect(math("(2+3)*4") == "20", "parentheses come first")
        expect(math("2+3*4") == "14", "multiplication binds tighter than addition")
        expect(math("10/4") == "2.5", "division keeps its decimals")
        expect(math("2^3^2") == "512", "powers group to the right")
        expect(math("-5+2") == "-3", "a leading minus is a sign, not an error")
        expect(math("--5+1") == "6", "two minuses cancel")
        expect(math("1920/2") == "960", "the everyday case works")
        expect(value("0.1+0.2") == 0.3 && math("0.1+0.2") == "0.3",
               "floating point noise never reaches the eye")
        expect(math("1,000+1") == "1,001", "grouped thousands parse and print grouped")
        expect(math("2 x 3") == "6" && math("10 ÷ 2") == "5" && math("2 × 3") == "6",
               "the written multiplication and division signs work too")
        expect(math("2(3+4)") == "14" && math("(1+2)(3+4)") == "21",
               "a number against a parenthesis multiplies")
        expect(math("-2^2") == "-4", "a sign applies to the whole power, as on paper")
        expect(math("2^0.5")?.hasPrefix("1.41421") == true, "a fractional power is fine")
        expect(math("1/1000000000") == "1e-9", "a billionth reads as a billionth, not as zero")
        expect(math("2^100")?.contains("e") == true,
               "a huge answer switches notation instead of vanishing")

        // MARK: Dates and sums that only look alike

        expect(math("2026-07-27") == nil && math("27/07/2026") == nil && math("10:30") == nil,
               "a date or a time is never answered as a sum")
        expect(math("100-50") == "50", "two numbers around a minus are still a subtraction")
        expect(math("100 - 20 - 30") == "50" && math("2 - 1 - 1") == "0" && math("8 / 2 / 2") == "2",
               "three numbers spaced apart are a sum, since no date is written that way")
        expect(math("10-5-3") == nil && math("8/2/2") == nil && math("10 : 30") == nil,
               "the unspaced shapes that can be a date, and a spaced time, are still left alone")
        expect(math("SDL_VIDEODRIVER=") == nil && math("x=5") == nil,
               "an assignment shape is not an expression")
        expect(math("7+3=") == "10", "a trailing equals sign is just habit")

        // MARK: Percentages

        expect(math("480+15%") == "552", "a percentage after plus is relative")
        expect(math("480-15%") == "408", "and after minus too")
        expect(math("20% of 480") == "96", "percent of a number reads as it is said")
        expect(math("20% de 480") == "96", "the same in the other words people type")
        expect(math("50%") == nil, "a lone percentage is not a question")
        expect(math("200*10%") == "20", "a percentage multiplies as a fraction")

        // MARK: What must stay a search

        expect(math("5") == nil, "a lone number is a search, not an answer")
        expect(math("hello") == nil, "words are not expressions")
        expect(math("1password") == nil, "an app name that starts with a digit stays a search")
        expect(math("volume 20") == nil, "a command with a number is not a sum")
        expect(math("brilho 40") == nil, "neither is the same command in another language")
        expect(math("10/0") == nil, "dividing by zero has no answer to show")
        expect(math("2+") == nil && math("(2+3") == "5" && math("2++") == nil,
               "only missing closing brackets are supplied virtually")
        expect(math("2 * -3") == "-6", "a sign after an operator is read as a sign")
        expect(math(String(repeating: "(", count: 60) + "1" + String(repeating: ")", count: 60)) == nil,
               "a wall of parentheses is refused instead of eating the stack")
        expect(math("e-mail") == nil, "a hyphenated word is not a subtraction")
        expect(math("9999999999999999*99")?.contains("e") == true,
               "a number past plain reading switches notation")

        // MARK: The same numbers as this Mac writes them

        expect(CommandBarMath.evaluate("1.234,5 + 1",
                                       decimalSeparator: ",",
                                       groupingSeparator: ".",
                                       locale: Locale(identifier: "pt_BR"))?.formatted == "1.235,5",
               "a comma decimal parses and prints back in the same shape")
        expect(CommandBarMath.evaluate("1,5*2",
                                       decimalSeparator: ",",
                                       groupingSeparator: ".",
                                       locale: Locale(identifier: "pt_BR"))?.value == 3,
               "the comma is the decimal point where that is the custom")
        expect(math("1.500+1", decimal: ",", grouping: ".") == "1,501",
               "three digits after the grouping separator read as thousands")

        // MARK: Macs that group thousands with a space or an apostrophe

        for (name, grouping) in [("pt_PT", "\u{00A0}"), ("fr_FR", "\u{202F}")] {
            expect(value("1.5+1", decimal: ",", grouping: grouping) == 2.5
                    && value("0.1+0.2", decimal: ",", grouping: grouping) == 0.3,
                   "a dot decimal still works where the comma is the decimal point: \(name)")
            expect(value("1.500+1", decimal: ",", grouping: grouping) == 1501
                    && value("1.234,5+1", decimal: ",", grouping: grouping) == 1235.5
                    && value("1,234.5+1", decimal: ",", grouping: grouping) == 1235.5,
                   "the dot reads as thousands only when it looks the part: \(name)")
            expect(value("1\(grouping)234,5+1", decimal: ",", grouping: grouping) == 1235.5,
                   "the Mac's own grouping space still reads as thousands: \(name)")
            expect(value("1\(grouping)5+1", decimal: ",", grouping: grouping) == nil,
                   "a grouping space is never a decimal point: \(name)")
            expect(value("1\(grouping)234,5\(grouping)67+1", decimal: ",", grouping: grouping) == nil
                    && value("1\(grouping)234.5\(grouping)67+1", decimal: ",", grouping: grouping) == nil,
                   "grouping spaces cannot silently join digits after either decimal point: \(name)")
        }

        expect(value("1,5+1", decimal: ".", grouping: "'") == 2.5
                && value("1,234.5+1", decimal: ".", grouping: "'") == 1235.5
                && value("1'234.5+1", decimal: ".", grouping: "'") == 1235.5,
               "a comma decimal works where thousands are grouped with an apostrophe")
        expect(value("1'234.5'67+1", decimal: ".", grouping: "'") == nil
                && value("1'234,5'67+1", decimal: ".", grouping: "'") == nil,
               "an apostrophe in the fractional part is rejected instead of changing the number")
        expect(value("1.2.3+1", decimal: ",", grouping: "\u{00A0}") == nil,
               "a repeated alternate separator that is not thousands has no answer")

        // A grouping space or apostrophe groups only when digits follow it.
        expect(value("1\u{00A0}+ 2", decimal: ",", grouping: "\u{00A0}") == 3,
               "a no-break space after a number before an operator is just a space")
        expect(value("200*15\u{202F}%", decimal: ",", grouping: "\u{202F}") == 30,
               "a narrow no-break space before percent still answers")
        expect(value("2\u{00A0}(3)", decimal: ",", grouping: "\u{00A0}") == 6,
               "a no-break space before a bracket keeps the implicit product")
        expect(value("1,5\u{00A0}+ 2", decimal: ",", grouping: "\u{00A0}") == 3.5,
               "a decimal followed by a no-break space reads as that decimal")
        expect(value("1\u{00A0}234\u{00A0}+ 1", decimal: ",", grouping: "\u{00A0}") == 1235,
               "grouped thousands followed by a no-break space still answer")
        expect(value("1\u{00A0}5+1", decimal: ",", grouping: "\u{00A0}") == nil,
               "a grouping space between digits is never a decimal point")

        // Thousands never start at zero.
        for (decimal, grouping) in [(",", "\u{00A0}"), (",", "\u{202F}"), (".", "'"), (",", "."), (".", ",")] {
            let alternate = decimal == "," ? "." : ","
            expect(value("0\(alternate)125*8", decimal: decimal, grouping: grouping) == 1
                    && value("0\(alternate)500+1", decimal: decimal, grouping: grouping) == 1.5,
                   "a number that starts at zero has decimals, never thousands, with \(decimal) and \(grouping)")
        }
        expect(value("0\u{00A0}125+1", decimal: ",", grouping: "\u{00A0}") == nil,
               "a grouping space after a lone zero is not thousands")

        // MARK: Virtual brackets and named functions

        expect(CommandBarMath.evaluate("([2+3")?.closingBrackets == "])"
                && CommandBarMath.evaluate("2+3")?.closingBrackets == "",
               "virtual closers preserve bracket kind and nesting")
        expect(value("sqrt(81") == 9 && value("2*(3+[4") == 14,
               "functions and nested brackets evaluate before closers are typed")
        for expression in ["(2+3]", "2+3)", "2*(3+", "sqrt(", "sin2", "log100(2)",
                           "sqrt(-1)", "log(0)", "acos(2)", "1e309+0", "7=+3", "7+3=="] {
            expect(value(expression) == nil
                    && CommandBarMath.evaluate(expression)?.closingBrackets == nil,
                   "invalid calculator input has neither an answer nor ghost brackets: \(expression)")
        }
        for (expression, expected) in [
            ("sqrt(9)+abs(-3)", 6.0), ("sin(pi/2)+cos(0)+tan(0)", 2.0),
            ("asin(1)+acos(1)+atan(1)", Double.pi * 0.75),
            ("ln(exp(1))+log(100)+log10(100)", 5.0),
            ("floor(1.9)+ceil(1.1)+round(1.5)", 5.0),
            ("2pi", 2 * Double.pi), ("π+e", Double.pi + Foundation.exp(1)),
            ("2x3+2 x 4", 14.0), ("2(3)+(2)(3)+2[3]", 18.0), ("1e-9*1e9", 1.0),
        ] {
            expect(value(expression).map { abs($0 - expected) < 1e-7 } ?? false,
                   "scientific calculator evaluates \(expression)")
        }
        expect(value("1,5e-3*2", decimal: ",", grouping: ".") == 0.003,
               "scientific mantissas respect decimal-comma locales")
        for (expression, expected) in [("sin(1e-13)*1e13", 1.0),
                                       ("tan(1e-13)*1e13", 1.0),
                                       ("sin(-1e-13)*1e13", -1.0),
                                       ("1/sin(1e-13)", 1e13),
                                       ("cos(pi/2+1e-13)/cos(pi/2+1e-13)", 1.0)] {
            expect(value(expression) == expected,
                   "small trigonometric values remain available to the rest of the calculation: \(expression)")
        }

        // MARK: An answer put back into the field

        for expression in ["0.1+0.2", "1/3", "-2^2", "1e-9+0", "2^100"] {
            if let result = CommandBarMath.evaluate(expression,
                                                    decimalSeparator: ".",
                                                    groupingSeparator: ",") {
                let reusable = CommandBarMath.reusableExpression(for: result, decimalSeparator: ".")
                expect(value(reusable + "+0") == result.value,
                       "reusing \(expression) preserves its stored value")
                if result.value == 0.3 {
                    expect(reusable == "0.3", "reuse hides binary noise")
                }
                if result.value == -4 {
                    expect(value(reusable + "^2") == 16,
                           "negative reuse preserves power precedence")
                }
                let comma = CommandBarMath.reusableExpression(for: result, decimalSeparator: ",")
                expect(value(comma + "+0", decimal: ",", grouping: ".") == result.value,
                       "reused answers also round-trip in decimal-comma locales")
            } else {
                expect(false, "calculator produces an answer to reuse for \(expression)")
            }
        }
    }
}
