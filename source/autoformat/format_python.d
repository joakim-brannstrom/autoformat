/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

autoformatter for python.
Defaults to autopep8 because it works.
*/
module autoformat.format_python;

import std.algorithm;
import std.array;
import std.conv : to;
import std.exception;
import std.file;
import std.string : join;
import std.process;
import logger = std.experimental.logger;

import std.typecons : Flag;

import autoformat.types;

private immutable string[] autopep8Conf = import("autopep8.conf").splitter("\n")
    .filter!(a => a.length > 0).array();

// TODO dry_run not supported.
auto runPythonFormatter(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) {
    if (dry_run) {
        return FormatterResult(FormatterStatus.unchanged);
    }

    string[] opts = autopep8Conf.map!(a => a.idup).array();

    auto rval = FormatterResult(FormatterStatus.error);

    try {
        if (backup) {
            copy(fname, fname ~ ".orig");
        }

        auto arg = ["autopep8"] ~ opts ~ [cast(string) fname];
        logger.trace(arg.join(" "));
        auto res = execute(arg);
        logger.trace(res.output);

        if (dry_run) {
            rval = FormatterStatus.unchanged;
        } else {
            rval = FormatterStatus.formattedOk;
        }
    }
    catch (ErrnoException ex) {
        rval = FormatterResult(ex.msg);
    }

    return rval;
}
