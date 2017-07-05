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
    .filter!(a => a.length > 0).array() ~ ["-Q"];

auto runAstyle(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) {
    string[] opts = astyleConf.map!(a => a.idup).array();

    if (backup) {
        opts ~= "--suffix=.orig";
    } else {
        opts ~= "--suffix=none";
    }

    if (dry_run) {
        opts ~= ["--dry-run"];
    }

    auto rval = FormatterResult(FormatterStatus.error);

    try {
        auto arg = ["astyle"] ~ opts ~ [cast(string) fname];
        logger.trace(arg.join(" "));
        auto res = execute(arg);
        logger.trace(res.output);

        if (dry_run && res.output.length != 0) {
            rval = FormatterResult(FormatterStatus.wouldChange);
        } else if (res.output.length != 0) {
            rval = FormatterStatus.formattedOk;
        } else {
            rval = FormatterStatus.unchanged;
        }
    }
    catch (ErrnoException ex) {
        rval = FormatterResult(ex.msg);
    }

    return rval;
}
