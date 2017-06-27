/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains functions for git repos.
*/
module autoformat.git;

import std.exception;
import std.file;
import std.path;
import std.process;
import std.variant;

import autoformat.types;

bool isGitRoot(AbsolutePath arg_p) {
    if (!exists(arg_p)) {
        return false;
    } else if (exists(buildPath(arg_p, ".git", "refs"))) {
        // all is well! a real git repo found
        return true;
    } else if (exists(buildPath(arg_p, "refs"))) {
        // humpf, submodule
        return true;
    }

    return false;
}

auto gitHookPath(AbsolutePath repo) {
    alias Result = Algebraic!AbsolutePath;

    immutable regular = buildPath(repo, ".git", "hooks");
    immutable submodule = buildPath(repo, "hooks");

    if (exists(regular)) {
        return Result(AbsolutePath(regular));
    } else if (exists(buildPath(repo, "refs"))) {
        return Result(AbsolutePath(submodule));
    }

    return Result();
}

/// Path to the root of the git archive from current.
AbsolutePath gitPathToRoot() {
    import std.string : strip;

    auto r = execute(["git", "rev-parse", "--show-toplevel"]);
    return AbsolutePath(r.output.strip);
}

/** Resolves the path to the git directory.
 * Not necessarily the same as the root.
 * Useful for finding the root of a hierarchy of submodules.
 */
AbsolutePath gitPathToTrueRoot() {
    import std.string : strip;

    auto p = buildPath(gitPathToRoot, ".git");
    auto r = execute(["git", "rev-parse", "--resolve-git-dir", p]);
    return AbsolutePath(r.output.strip);
}

string gitConfigValue(string c) {
    import std.string : strip;

    try {
        auto a = execute(["git", "config", c]);
        if (a.status != 0) {
            return null;
        }

        return a.output.strip;
    }
    catch (ErrnoException ex) {
    }

    return null;
}
