/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

The only purpose of this file is to redirect the execution of integration tests
from the main directory to the subdirectory test.

It is NOT intended to be used for anything else.
*/
module autoformat.test.redirect;

import std.file;
import std.process;
import std.stdio;
import std.path;

int main(string[] args) {
    writeln("===============================");
    writeln("Redirecting testing to: ", buildPath(getcwd, "test"));

    // make sure the grammar is pristine
    if (spawnProcess(["dub", "build", "-c", "application"]).wait != 0) {
        return -1;
    }

    chdir("test");

    if (spawnProcess(["dub", "build"]).wait != 0) {
        return -1;
    }

    auto pid = spawnProcess(["dub", "test", "--", "-d"]);
    return pid.wait != 0;
}
