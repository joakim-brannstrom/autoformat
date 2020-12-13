/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains the integration tests of autoformat.
The intent is to test autoformat as if it is a black box. As a user would use
the tool.
*/
module integration;

import std.algorithm;
import std.ascii;
import std.conv;
import std.file;
import std.getopt;
import std.process;
import std.path;
import core.stdc.stdlib;
import std.range;
import std.regex;
import std.stdio;
import std.string;
import logger = std.experimental.logger;

import my.test;

string autoformatBinary = "../build/autoformat";
bool debugMode = false;
immutable bool[string] tools;

shared static this() {
    // check that the tools are installed
    foreach (a; ["astyle", "clang-format", "dfmt"]) {
        auto r = std.process.execute(["which", a]);
        r.output.write;
        tools[a] = r.status == 0;
    }
}

unittest {
    import std.string : startsWith;

    autoformatBinary = autoformatBinary.absolutePath;
    logger.globalLogLevel = logger.LogLevel.all;
    logger.info("Using this binary when testing: ", autoformatBinary);

    sanityCheck;

    foreach (t; ["clang-format"]) {
        writeln("Tool ", t);

        import core.sys.posix.stdlib : putenv, unsetenv;

        const env_key = "AUTOFORMAT_CLANG_TOOL";
        const env_var = (env_key ~ "=" ~ t).toStringz;
        putenv(cast(char*) env_var);

        testFormatOneFile();
        testFormatFiles();
        testLongLineFormatting();
        testFormatFilesInGitRepo();
        testFormatUnknownFiletype();
        testInstallGitHook();
        testInjectGitHook();
        testGitHookAuto();
        testGitHookWarn();
        testGitHookInterrupt();
        testBackup();
        testNoBackup();
        testDryRun();
        testRecursive();
        testRecursiveSkipDir();
        testSetup();
    }

    if ("dfmt" in tools) {
        testFormatOneFileD();
        testFormatFilesInGitRepoD();
    }

    testTrailingWhitespaceDetector();
    testDetab();
}

void sanityCheck() {
    auto p = environment.get("PATH");
    writeln("Path is: ", p);
    writeln("Tools: ", tools);
    writeln;
}

void testFormatOneFile() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createUnformattedCpp("a.h");
    createUnformattedCpp("a.hpp");
    createUnformattedPython("a.py");

    assert(autoformat(ta, "a.h").status == 0);
    assert(autoformat(ta, "a.hpp").status == 0);
    assert(autoformat(ta, "a.py").status == 0);

    // should be resiliant against non-existing files.
    // do not error out on them.
    assert(autoformat(ta, "a.foo").status == 0);
}

void testFormatOneFileD() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createUnformattedD("a.d");

    assert(autoformat(ta, "a.d").status == 0);
}

void testFormatFiles() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createUnformattedCpp("a.h");
    createUnformattedCpp("b.h");
    createUnformattedCpp("c.hpp");

    assert(autoformat(ta, "a.h", "b.h", "c.hpp").status == 0);

    assert(exists("a.h.orig"));
    assert(exists("b.h.orig"));
    assert(exists("c.hpp.orig"));
}

void testFormatFilesInGitRepo() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;

    createRepo(ta);
    ta.exec("touch", "a.hpp");
    assert(autoformat(ta, "a.hpp").status == 0);
}

void testFormatFilesInGitRepoD() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createRepo(ta);
    ta.exec("touch", "a.d");
    assert(autoformat(ta, "a.d").status == 0);
}

void testFormatUnknownFiletype() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    ta.exec("touch", "a.x");
    assert(autoformat(ta, "a.x").status == 0);
}

void testInstallGitHook() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createRepo(ta);

    assert(autoformat(ta, "-i", ta.sandboxPath).status == 0);

    assert(exists(buildPath(ta.sandboxPath, ".git", "hooks", "pre-commit")));
    assert(exists(buildPath(ta.sandboxPath, ".git", "hooks", "prepare-commit-msg")));
    assert(exists(buildPath(ta.sandboxPath, ".git", "hooks", "autoformat_pre-commit")));
    assert(exists(buildPath(ta.sandboxPath, ".git", "hooks", "autoformat_prepare-commit-msg")));
}

void testInjectGitHook() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createRepo(ta);

    assert(autoformat(ta, "-i", ta.sandboxPath).status == 0);
    // should be possible to run multiple times but the injected hook occurs
    // only once
    assert(autoformat(ta, "-i", ta.sandboxPath).status == 0);

    auto pre_commit = std.file.readText(buildPath(ta.sandboxPath, ".git", "hooks", "pre-commit"));
    assert(!matchAll(pre_commit,
            `.*\$\(git rev-parse --git-dir\)/hooks/autoformat_pre-commit \$@.*`).empty);
    auto prepare_commit_msg = std.file.readText(buildPath(ta.sandboxPath,
            ".git", "hooks", "prepare-commit-msg"));
    assert(!matchAll(prepare_commit_msg,
            `.*\$\(git rev-parse --git-dir\)/hooks/autoformat_prepare-commit-msg \$@.*`).empty);
}

void testBackup() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createUnformattedCpp("a.h");
    autoformat(ta, "a.h");
    assert(exists(buildPath(ta.sandboxPath, "a.h.orig")));
}

void testNoBackup() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createUnformattedCpp("a.h");
    autoformat(ta, "--no-ta, backup", "a.h");
    assert(!exists(buildPath(ta.sandboxPath, "a.h.orig")));
}

void testDryRun() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createUnformattedCpp("a.h");

    autoformat(ta, "-n", "a.h");

    assert(!exists("a.h.orig"));
    assert(std.file.readText("a.h") == unformattedFileCpp);
}

void testGitHookAuto() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createRepo(ta);
    autoformat(ta, "-i", ".");
    createUnformattedCpp("a.h");
    git(ta, "config", "hooks.autoformat", "auto");

    git(ta, "add", "a.h");
    git(ta, "commit", "-am", "foo");

    assert(!exists("a.h.orig"));
    assert(std.file.readText("a.h") != unformattedFileCpp);
}

void testGitHookWarn() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createRepo(ta);
    autoformat(ta, "-i", ".");
    createUnformattedCpp("a.h");
    git(ta, "config", "hooks.autoformat", "warn");

    git(ta, "add", "a.h");
    auto res = git(ta, "commit", "-am", "foo");

    assert(!matchFirst(res.output, ".*WARNING the following files need to be formatted").empty);
    assert(!exists("a.h.orig"));
    assert(std.file.readText("a.h") == unformattedFileCpp);
}

void testGitHookInterrupt() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createRepo(ta);
    autoformat(ta, "-i", ".");
    createUnformattedCpp("a.h");
    git(ta, "config", "hooks.autoformat", "interrupt");

    git(ta, "add", "a.h");
    auto res = git(ta, "commit", "-am", "foo");

    assert(res.status != 0);
    assert(!matchFirst(res.output, ".*Commit interrupted because unformatted files found").empty);
    assert(!exists("a.h.orig"));
    assert(std.file.readText("a.h") == unformattedFileCpp);
}

void testRecursive() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    string base_dir;
    foreach (i; 0 .. 101) {
        if (i % 10 == 0) {
            base_dir = "d" ~ i.to!string;
            mkdir(base_dir);
        }

        if (i == 55) {
            ta.exec("touch", buildPath(base_dir, "wrong_filetype.apa"));
        } else {
            createUnformattedCpp(buildPath(base_dir, "file_" ~ i.to!string ~ ".cpp"));
        }
    }

    assert(autoformat(ta, "-r", ta.sandboxPath).status == 0);
    assert(dirEntries(".", SpanMode.depth).filter!(a => a.baseName.endsWith(".orig")).count == 100);
}

// shall skip the directory which contains the magic file.
void testRecursiveSkipDir() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    string base_dir;
    foreach (i; 0 .. 101) {
        if (i % 10 == 0) {
            base_dir = "d" ~ i.to!string;
            mkdir(base_dir);
        }

        if (i == 55) {
            ta.exec("touch", buildPath(base_dir, ".noautoformat"));
        } else if (i == 72) {
            ta.exec("touch", buildPath(base_dir, ".noautoformat"));
        } else {
            createUnformattedCpp(buildPath(base_dir, "file_" ~ i.to!string ~ ".cpp"));
        }
    }

    assert(autoformat(ta, "-r", ta.sandboxPath).status == 0);
    assert(dirEntries(".", SpanMode.depth).filter!(a => a.baseName.endsWith(".orig")).count == 81);
}

void testSetup() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    assert(autoformat(ta, "--setup").status == 0);
    assert(exists(buildPath(autoformatBinary.dirName, "autoformat_src")));
    assert(exists(buildPath(autoformatBinary.dirName, "autoformat_src.py")));
}

void testTrailingWhitespaceDetector() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createRepo(ta);

    // the tool shall report no error
    assert(autoformat(ta, "--check-trailing-whitespace").status == 0);

    // the tool shall report no error because the file is not staged
    createTrailingWhitespaceFile("a.h");
    assert(autoformat(ta, "--check-trailing-whitespace").status == 0);

    // the tool shall report an error
    git(ta, "add", "a.h");
    assert(autoformat(ta, "--check-trailing-whitespace").status != 0);
}

void testDetab() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createTrailingWhitespaceFile("a.txt");

    auto r = autoformat(ta, "--tool-detab", "a.txt");
    assert(r.status == 0);

    assert(exists("a.txt.orig"));
    auto content = std.file.readText("a.txt");
    assert(content == "void f();\n");
}

void testLongLineFormatting() {
    auto ta = makeTestArea(__FUNCTION__);
    ta.chdirToSandbox;
    createLongLineCpp("long.hpp");
    assert(autoformat(ta, "long.hpp").status == 0);
}

void createRepo(ref TestArea ta) {
    git(ta, "init", ".");
    ta.exec("touch", ".gitignore");
    git(ta, "add", ".gitignore");
    git(ta, "commit", "-am", "here be dragons");
}

auto git(T...)(ref TestArea ta, T args_) {
    return ta.exec("git", args_);
}

auto autoformat(T...)(ref TestArea ta, auto ref T args_) {
    return ta.exec(autoformatBinary, "--vverbose", args_);
}

void createSandboxFile(string content, string dst) {
    File(dst, "w").write(content);
}

immutable unformattedFileCpp = "   void f(int* x)\n{}\n";
alias createUnformattedCpp = dst => createSandboxFile(unformattedFileCpp, dst);

immutable longLineCpp = "namespace this_is_a_very_long_namespace_just_to_create_a_line { namespace that_is_longer_than_100_letters { namespace as_to_force_funky_behavior { typedef int MyInt; }}}
namespace foo {
class A {
public:
void method(this_is_a_very_long_namespace_just_to_create_a_line::this_is_a_very_long_namespace_just_to_create_a_line::as_to_force_funky_behavior::MyInt a, this_is_a_very_long_namespace_just_to_create_a_line::this_is_a_very_long_namespace_just_to_create_a_line::as_to_force_funky_behavior::MyInt b, int c);
};
}
";
alias createLongLineCpp = dst => createSandboxFile(longLineCpp, dst);

immutable unformattedFilePython = "def f(): \n return 1";
alias createUnformattedPython = dst => createSandboxFile(unformattedFilePython, dst);

immutable unformattedFileD = "   void f(int* x)\n{}\n";
alias createUnformattedD = dst => createSandboxFile(unformattedFileD, dst);

immutable trailingWhitespaceFile = "void f();   \n";
alias createTrailingWhitespaceFile = dst => createSandboxFile(trailingWhitespaceFile, dst);
