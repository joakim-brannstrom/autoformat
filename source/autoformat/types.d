/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module autoformat.types;

import std.variant : Algebraic;

struct Path {
    string payload;
    alias payload this;
}

/** The path is guaranteed to be the absolute path.
 *
 * The user of the type has to make an explicit judgment when using the
 * assignment operator. Either a `FileName` and then pay the cost of the path
 * expansion or an absolute which is already assured to be _ok_.
 * This divides the domain in two, one unchecked and one checked.
 */
struct AbsolutePath {
    import std.path : expandTilde, buildNormalizedPath, absolutePath;

    Path payload;
    alias payload this;

    invariant {
        import std.path : isAbsolute;

        assert(payload.length == 0 || payload.isAbsolute);
    }

    this(string p) nothrow {
        try {
            auto p_expand = () @trusted{ return p.expandTilde; }();
            payload = buildNormalizedPath(p_expand).absolutePath.Path;
        }
        catch (Exception ex) {
            payload = null;
        }
    }

    this(AbsolutePath p) nothrow {
        this = p;
    }

    void opAssign(string p) {
        payload = typeof(this)(p).payload;
    }

    pure nothrow @nogc void opAssign(AbsolutePath p) {
        payload = p.payload;
    }
}

enum FormatterStatus {
    /// failed to format or some other kind of error
    error,
    /// error when formatting with an error msg
    failedWithUserMsg,
    ///
    unchanged,
    /// formatted file with no errors
    formattedOk,
    /// The file would change if it where autoformatted
    wouldChange,
}

struct FormatterResult {
    FormatterStatus status;
    string msg;

    alias status this;
}
