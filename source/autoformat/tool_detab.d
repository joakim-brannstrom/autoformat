/* Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE_1_0.txt or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */

/* Replace tabs with spaces, and remove trailing whitespace from lines.
 */

// Derived from git://github.com/D-Programming-Language/tools.git
module autoformat.tool_detab;

import std.file;
import std.path;
import std.typecons : Flag;
import logger = std.experimental.logger;

import autoformat.types;

auto runDetab(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    auto rval = FormatterResult(FormatError.init);

    char[] input;
    try {
        input = cast(char[]) std.file.read(cast(string) fname);
    } catch (Exception ex) {
        rval = FailedWithUserMsg(ex.msg);
        return rval;
    }

    char[] output;
    try {
        output = filter(input);
    } catch (Exception e) {
        rval = WouldChange.init;
        return rval;
    }

    if (input == output) {
        rval = Unchanged.init;
        return rval;
    }

    if (dry_run) {
        rval = WouldChange.init;
        return rval;
    }

    try {
        if (backup) {
            copy(fname, fname.toString ~ ".orig");
        }

        std.file.write(fname, output);
        rval = FormattedOk.init;
    } catch (Exception ex) {
        rval = FailedWithUserMsg(ex.msg);
    }

    return rval;
}

char[] filter(char[] input) {
    char[] output;
    size_t j;

    int column;
    for (size_t i = 0; i < input.length; i++) {
        auto c = input[i];

        switch (c) {
        case '\t':
            while ((column & 7) != 7) {
                output ~= ' ';
                j++;
                column++;
            }
            c = ' ';
            column++;
            break;

        case '\r':
        case '\n':
            while (j && output[j - 1] == ' ')
                j--;
            output = output[0 .. j];
            column = 0;
            break;

        default:
            column++;
            break;
        }
        output ~= c;
        j++;
    }
    while (j && output[j - 1] == ' ')
        j--;
    return output[0 .. j];
}
