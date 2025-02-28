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
import std.stdio;

import logger = std.experimental.logger;

import autoformat.types;
import autoformat.common : loggedExecute;

private immutable string[] clangFormatConf = import("clang_format.conf").splitter(
        "\n").filter!(a => a.length != 0).array;

// Thread local optimization that reduced the console spam when the program
// isn't installed.
private bool installed = true;

immutable clangToolEnvKey = "AUTOFORMAT_CLANG_TOOL";

string getClangFormatterTool() @safe nothrow {
    try {
        return environment.get(clangToolEnvKey, "clang-format");
    } catch (Exception e) {
    }
    return "clang-format";
}

bool isClangFormatSupportedConfigDump(ConfigDumpCommand lang) nothrow {
    return lang == ConfigDumpCommand.cpp;
}

auto runClangFormatter(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    return runClangFormat(fname, getClangFormatterTool, backup, dry_run);
}

auto runClangFormat(AbsolutePath fname, string clangFormatExec,
        Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    import std.file : copy;

    string[] opts = clangFormatConf.map!(a => a.idup).array;

    if (!installed) {
        return FormatterResult(Unchanged.init);
    }

    if (dry_run)
        opts ~= "-output-replacements-xml";
    else
        opts ~= "-i";

    auto arg = [clangFormatExec] ~ opts ~ [cast(string) fname];

    auto rval = FormatterResult(FormatError.init);

    try {
        if (!dry_run && backup) {
            copy(fname, fname.toString ~ ".orig");
        }

        auto res = loggedExecute(arg);

        if (dry_run) {
            if (hasFormattingHints(res.output)) {
                rval = FormatterResult(WouldChange.init);
            } else {
                rval = FormatterResult(Unchanged.init);
            }
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

bool hasFormattingHints(string output) nothrow {
    import dxml.parser;

    try {
        return parseXML(output).filter!(a => a.type == EntityType.elementStart
                && a.name == "replacement").count != 0;
    } catch (Exception e) {
        logger.tracef("unable to XML parse '%s' : %s", output, e.msg).collectException;
    }
    return false;
}

int dumpClangFormatConfig() nothrow {
    try {
        auto cmd = [getClangFormatterTool] ~ clangFormatConf.map!(a => a.idup)
            .array ~ "--dump-config";
        logger.trace(cmd);
        auto ecode = spawnProcess(cmd).wait;
        if (ecode != 0)
            logger.warning("Failed dumping clang-format config");
        return ecode;
    } catch (Exception e) {
        logger.warning("Cannot dump clang-format config: e.msg").collectException;
    }
    return 1;
}
