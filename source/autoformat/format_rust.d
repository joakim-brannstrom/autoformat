/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module autoformat.format_rust;

import std.algorithm;
import std.array;
import std.exception;
import std.file;
import std.string : join;
import std.process;
import logger = std.experimental.logger;

import std.typecons : Flag;

import autoformat.types;

// Thread local optimization that reduced the console spam when the program
// isn't installed.
private bool installed = true;

auto runRustFormatter(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    if (!installed) {
        return FormatterResult(Unchanged.init);
    }

    string[] opts;

    if (dry_run)
        opts ~= "--check";
    else if (backup)
        opts ~= "--backup";

    auto rval = FormatterResult(FormatError.init);

    try {
        auto arg = ["rustfmt"] ~ opts ~ (cast(string) fname);
        logger.trace(arg.join(" "));
        auto res = execute(arg);
        logger.trace(res.output);

        rval = FormattedOk.init;
    } catch (ProcessException ex) {
        // rustfmt isn't installed
        rval = FailedWithUserMsg(ex.msg);
        installed = false;
    } catch (Exception ex) {
        rval = FailedWithUserMsg(ex.msg);
    }

    return rval;
}
