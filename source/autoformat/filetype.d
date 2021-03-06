/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

This file contains the checkers for different languages.
*/
module autoformat.filetype;

import std.array : array;
import std.algorithm;
import std.file;
import std.path;

import autoformat.git;
import autoformat.types;

enum filetypeCheckers = [&isC_CppFiletype, &isDFiletype, &isRustFiletype];

immutable string[] suppressAutoformatFilenames = import("magic_suppress_autoformat_filenames.conf")
    .splitter("\n").filter!(a => a.length > 0).array();

bool isFiletypeSupported(AbsolutePath p) nothrow {
    foreach (f; filetypeCheckers) {
        if (f(p.extension)) {
            return true;
        }
    }

    return false;
}

bool isC_CppFiletype(string p) nothrow {
    enum types = import("filetype_c_cpp.txt").splitter.array();
    return types.canFind(p) != 0;
}

bool isDFiletype(string p) nothrow {
    enum types = import("filetype_d.txt").splitter.array();
    return types.canFind(p) != 0;
}

bool isRustFiletype(string p) nothrow {
    enum types = import("filetype_rust.txt").splitter.array();
    return types.canFind(p) != 0;
}

auto isOkToFormat(AbsolutePath p) nothrow {
    struct Result {
        string payload;
        bool ok;
    }

    auto res = Result(null, true);

    if (!exists(p)) {
        res = Result("file not found: " ~ p);
    } else if (!isFiletypeSupported(p)) {
        res = Result("filetype not supported: " ~ p);
    } else {
        string w = p;
        while (w != "/") {
            foreach (check; suppressAutoformatFilenames.map!(a => buildPath(w, a))) {
                if (exists(check)) {
                    return Result("autoformat of '" ~ p ~ "' blocked by: " ~ check);
                }
            }

            try {
                auto a = AbsolutePath(w);
                if (isGitRoot(a)) {
                    break;
                }
            } catch (Exception ex) {
            }

            w = dirName(w);
        }
    }

    return res;
}
