/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

The implementation currently uses the builtin checker that exist in git. The
intention though is to have a checker that doesn't relay on git, independent.

TODO:
 * whitespace check of specific files.
 * checker that can work without git.
*/
module autoformat.tool_whitespace_check;

import std.algorithm;
import std.array;
import std.exception;
import std.process : execute;

import logger = std.experimental.logger;

import autoformat.git : isGitRepo, gitHead;
import autoformat.types;

auto runWhitespaceCheck() nothrow {
    final switch (isGitDirectory) {
    case GitDirectory.unknown:
        isGitDirectory = GitDirectory.other;

        try {
            import std.file : getcwd;

            if (isGitRepo == 0) {
                return FormatterResult(FailedWithUserMsg("Trailing whitespace detector only work when ran from inside a git repo. The current directory is NOT a git repo: " ~ getcwd));
            }
        } catch (Exception ex) {
            return FormatterResult(FailedWithUserMsg(
                    "Aborting trailing whitespace check, unable to determine if the current directory is a git repo"));
        }

        isGitDirectory = GitDirectory.git;
        break;
    case GitDirectory.git:
        break;
    case GitDirectory.other:
        return FormatterResult(Unchanged.init);
    }

    auto rval = FormatterResult(FormatError.init);
    auto against = gitHead;

    try {
        auto arg = ["git", "diff-index", "--check", "--cached", against, "--"];
        logger.trace(arg.join(" "));
        auto res = execute(arg);
        logger.trace(res.output);

        if (res.status == 0) {
            rval = Unchanged.init;
        } else {
            rval = FailedWithUserMsg(
                    "Trailing whitespace check failed. Fix these files to pass the check:\n"
                    ~ res.output);
        }
    } catch (Exception ex) {
        rval = FailedWithUserMsg(ex.msg);
    }

    return rval;
}

private:

// Thread local detection if the current directory reside in a git archive.
GitDirectory isGitDirectory = GitDirectory.unknown;

enum GitDirectory {
    unknown,
    git,
    other
}
