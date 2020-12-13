/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file configures and imports the formatter tools that can be used.
*/
module autoformat.formatter_tools;

import std.typecons : Flag, Tuple;

public import autoformat.format_c_cpp;
public import autoformat.format_d;
public import autoformat.format_rust;
public import autoformat.filetype : isOkToFormat;

import autoformat.filetype;
import autoformat.types;

alias FormatterFunc = FormatterResult function(AbsolutePath p,
        Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow;
alias FormatterCheckFunc = bool function(string p);
alias Formatter = Tuple!(FormatterCheckFunc, FormatterFunc);

// dfmt off
enum formatters = [
    Formatter(&isC_CppFiletype, &runClangFormatter),
    Formatter(&isDFiletype, &runDfmt),
    Formatter(&isRustFiletype, &runRustFormatter),
];
// dfmt on
