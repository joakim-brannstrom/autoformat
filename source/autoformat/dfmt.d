/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains the integration needed for using dfmt to format D code.
*/
module autoformat.dfmt;

import std.exception;
import std.file;
import std.string : join;
import std.process;
import logger = std.experimental.logger;

import std.typecons : Flag;

import autoformat.types;

// dry_run not supported.
auto runDfmt(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) {
    auto opts = ["--inplace"];

    auto rval = FormatterResult(FormatterStatus.error);

    try {
        if (backup) {
            copy(fname, fname ~ ".orig");
        }

        auto arg = ["dfmt"] ~ opts ~ [cast(string) fname];
        logger.trace(arg.join(" "));
        auto res = execute(arg);
        logger.trace(res.output);

        rval = FormatterStatus.ok;
    }
    catch (ErrnoException ex) {
        rval = FormatterResult(ex.msg);
    }

    return rval;
}
