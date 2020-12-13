/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module autoformat.format_c_cpp;

import std.algorithm;
import std.array;
import std.exception;
import std.process;
import std.typecons : Flag;

import logger = std.experimental.logger;

import autoformat.types;

private immutable string[] astyleConf = import("astyle.conf").splitter("\n")
    .filter!(a => a.length > 0).array ~ ["-Q"];

private immutable string[] clangFormatConf = import("clang_format.conf").splitter(
        "\n").filter!(a => a.length != 0).array;

// Thread local optimization that reduced the console spam when the program
// isn't installed.
private bool installed = true;

immutable clangToolEnvKey = "AUTOFORMAT_CLANG_TOOL";

auto getClangFormatterTool() @safe nothrow {
    try {
        return environment.get(clangToolEnvKey, "clang-format");
    } catch (Exception e) {
    }
    return "astyle";
}

auto runClangFormatter(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    string tool = getClangFormatterTool;
    return runClangFormat(fname, backup, dry_run);
}

auto runClangFormat(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    import std.file : copy;

    string[] opts = clangFormatConf.map!(a => a.idup).array;

    if (!installed) {
        return FormatterResult(Unchanged.init);
    }

    if (dry_run)
        opts ~= "-output-replacements-xml";
    else
        opts ~= "-i";

    auto arg = ["clang-format"] ~ opts ~ [cast(string) fname];

    auto rval = FormatterResult(FormatError.init);

    try {
        if (!dry_run && backup) {
            copy(fname, fname.toString ~ ".orig");
        }

        auto res = loggedExecute(arg);

        if (dry_run && res.output.splitter("\n").count > 3) {
            rval = FormatterResult(WouldChange.init);
        } else {
            rval = FormatterResult(FormattedOk.init);
        }
    } catch (ProcessException e) {
        // clang-format isn't installed
        rval = FormatterResult(FailedWithUserMsg(e.msg));
        installed = false;
    } catch (Exception e) {
        rval = FormatterResult(FailedWithUserMsg(e.msg));
    }

    return rval;
}

auto loggedExecute(string[] arg) {
    logger.trace(arg.join(" "));
    auto res = execute(arg);
    logger.trace(res.output);
    return res;
}
