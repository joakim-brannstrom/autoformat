/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module autoformat.types;

import std.variant;

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
        import std.algorithm : canFind;
        import std.path : isAbsolute;

        assert(payload.length == 0 || payload.isAbsolute);
        // A path is absolute if it starts with a /.
        // But a ~ can be injected in the built, absolute path, when two or
        // more paths are combined with buildNormalizedPath and one of the
        // paths (not the first one) contains a ~.
        // This is functionally wrong, and even an invalid path.
        assert(!payload.payload.canFind('~'));
    }

    this(string p) {
        auto p_expand = () @trusted{ return p.expandTilde; }();
        payload = buildNormalizedPath(p_expand).absolutePath.Path;
    }

    this(AbsolutePath p) {
        this = p;
    }

    void opAssign(string p) {
        payload = typeof(this)(p).payload;
    }

    pure nothrow @nogc void opAssign(AbsolutePath p) {
        payload = p.payload;
    }
}
