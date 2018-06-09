#!/usr/bin/env rdmd
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

string autoformatBinary = "../build/autoformat";
bool debugMode = false;

int main(string[] args) {
    import std.string : startsWith;

    const string root = getcwd();
    autoformatBinary = autoformatBinary.absolutePath;
    logger.globalLogLevel = logger.LogLevel.all;
    logger.info("Using this binary when testing: ", autoformatBinary);

    getopt(args, std.getopt.config.keepEndOfOptions, "d|debug",
            "debug and keep the test directories", &debugMode);

    chdir("..");
    auto res = execute(["dub", "build"]);
    res.output.writeln;
    if (res.status != 0) {
        return -1;
    }
    chdir(root);

    sanityCheck;

    foreach (t; ["clang-format", "astyle"]) {
        writeln("Tool ", t);

        import core.sys.posix.stdlib : putenv, unsetenv;

        const env_key = "AUTOFORMAT_CLANG_TOOL";
        const env_var = (env_key ~ "=" ~ t).toStringz;
        putenv(cast(char*) env_var);

        testFormatOneFile(root);
        testFormatFiles(root);
        testFormatFilesInGitRepo(root);
        testFormatUnknownFiletype(root);
        testInstallGitHook(root);
        testInjectGitHook(root);
        testGitHookAuto(root);
        testGitHookWarn(root);
        testGitHookInterrupt(root);
        testBackup(root);
        testNoBackup(root);
        testDryRun(root);
        testRecursive(root);
        testRecursiveSkipDir(root);
        testSetup(root);
        testNotMultipleMessageWhenToolNotInstalled(root);
    }

    testTrailingWhitespaceDetector(root);
    testDetab(root);

    foreach (p; dirEntries(root, SpanMode.shallow).filter!(a => a.name.baseName.startsWith("tmp_"))) {
        if (debugMode) {
            writeln("rm -rf ", p);
        } else {
            run("rm", "-rf", p);
        }
    }

    return 0;
}

void sanityCheck() {
    auto p = environment.get("PATH");
    writeln("Path is: ", p);
    writeln;

    // check that the tools are installed
    foreach (a; ["astyle", "clang-format", "dfmt"]) {
        auto r = std.process.execute(["which", a]);
        r.output.write;
        assert(r.status == 0);
    }
}

void testFormatOneFile(const string root) {
    auto ta = TestArea(root);
    createUnformattedCpp("a.h");
    createUnformattedCpp("a.hpp");
    createUnformattedD("a.d");
    createUnformattedPython("a.py");

    assert(autoformat("a.h").status == 0);
    assert(autoformat("a.hpp").status == 0);
    assert(autoformat("a.d").status == 0);
    assert(autoformat("a.py").status == 0);

    // should be resiliant against non-existing files.
    // do not error out on them.
    assert(autoformat("a.foo").status == 0);
}

void testFormatFiles(const string root) {
    auto ta = TestArea(root);
    createUnformattedCpp("a.h");
    createUnformattedCpp("b.h");
    createUnformattedCpp("c.hpp");

    assert(autoformat("a.h", "b.h", "c.hpp").status == 0);

    assert(exists("a.h.orig"));
    assert(exists("b.h.orig"));
    assert(exists("c.hpp.orig"));
}

void testFormatFilesInGitRepo(const string root) {
    auto ta = TestArea(root);
    createRepo();
    run("touch", "a.hpp");
    run("touch", "a.d");
    assert(autoformat("a.hpp").status == 0);
    assert(autoformat("a.d").status == 0);
}

void testFormatUnknownFiletype(const string root) {
    auto ta = TestArea(root);
    run("touch", "a.x");
    assert(autoformat("a.x").status == 0);
}

void testInstallGitHook(const string root) {
    auto ta = TestArea(root);
    createRepo();

    assert(autoformat("-i", ta.root).status == 0);

    assert(exists(buildPath(ta.root, ".git", "hooks", "pre-commit")));
    assert(exists(buildPath(ta.root, ".git", "hooks", "prepare-commit-msg")));
    assert(exists(buildPath(ta.root, ".git", "hooks", "autoformat_pre-commit")));
    assert(exists(buildPath(ta.root, ".git", "hooks", "autoformat_prepare-commit-msg")));
}

void testInjectGitHook(const string root) {
    auto ta = TestArea(root);
    createRepo();

    assert(autoformat("-i", ta.root).status == 0);
    // should be possible to run multiple times but the injected hook occurs
    // only once
    assert(autoformat("-i", ta.root).status == 0);

    auto pre_commit = std.file.readText(buildPath(ta.root, ".git", "hooks", "pre-commit"));
    assert(!matchAll(pre_commit, `.*\$GIT_DIR/hooks/autoformat_pre-commit \$@.*`).empty);
    auto prepare_commit_msg = std.file.readText(buildPath(ta.root, ".git",
            "hooks", "prepare-commit-msg"));
    assert(!matchAll(prepare_commit_msg,
            `.*\$GIT_DIR/hooks/autoformat_prepare-commit-msg \$@.*`).empty);
}

void testBackup(const string root) {
    auto ta = TestArea(root);
    createUnformattedCpp("a.h");
    autoformat("a.h");
    assert(exists(buildPath(ta.root, "a.h.orig")));
}

void testNoBackup(const string root) {
    auto ta = TestArea(root);
    createUnformattedCpp("a.h");
    autoformat("--no-backup", "a.h");
    assert(!exists(buildPath(ta.root, "a.h.orig")));
}

void testDryRun(const string root) {
    auto ta = TestArea(root);
    createUnformattedCpp("a.h");

    autoformat("-n", "a.h");

    assert(!exists("a.h.orig"));
    assert(std.file.readText("a.h") == unformattedFileCpp);
}

void testGitHookAuto(const string root) {
    auto ta = TestArea(root);
    createRepo();
    autoformat("-i", ".");
    createUnformattedCpp("a.h");
    git("config", "hooks.autoformat", "auto");

    git("add", "a.h");
    git("commit", "-am", "foo");

    assert(!exists("a.h.orig"));
    assert(std.file.readText("a.h") != unformattedFileCpp);
}

void testGitHookWarn(const string root) {
    auto ta = TestArea(root);
    createRepo();
    autoformat("-i", ".");
    createUnformattedCpp("a.h");
    git("config", "hooks.autoformat", "warn");

    git("add", "a.h");
    auto res = git("commit", "-am", "foo");

    assert(!matchFirst(res.output, ".*WARNING the following files need to be formatted").empty);
    assert(!exists("a.h.orig"));
    assert(std.file.readText("a.h") == unformattedFileCpp);
}

void testGitHookInterrupt(const string root) {
    auto ta = TestArea(root);
    createRepo();
    autoformat("-i", ".");
    createUnformattedCpp("a.h");
    git("config", "hooks.autoformat", "interrupt");

    git("add", "a.h");
    auto res = git("commit", "-am", "foo");

    assert(res.status != 0);
    assert(!matchFirst(res.output, ".*Commit interrupted because unformatted files found").empty);
    assert(!exists("a.h.orig"));
    assert(std.file.readText("a.h") == unformattedFileCpp);
}

void testRecursive(const string root) {
    auto ta = TestArea(root);
    string base_dir;
    foreach (i; 0 .. 101) {
        if (i % 10 == 0) {
            base_dir = "d" ~ i.to!string;
            mkdir(base_dir);
        }

        if (i == 55) {
            run("touch", buildPath(base_dir, "wrong_filetype.apa"));
        } else {
            createUnformattedCpp(buildPath(base_dir, "file_" ~ i.to!string ~ ".cpp"));
        }
    }

    assert(autoformat("-r", ta.root).status == 0);
    assert(dirEntries(".", SpanMode.depth).filter!(a => a.baseName.endsWith(".orig")).count == 100);
}

// shall skip the directory which contains the magic file.
void testRecursiveSkipDir(const string root) {
    auto ta = TestArea(root);
    string base_dir;
    foreach (i; 0 .. 101) {
        if (i % 10 == 0) {
            base_dir = "d" ~ i.to!string;
            mkdir(base_dir);
        }

        if (i == 55) {
            run("touch", buildPath(base_dir, "matlab.xml"));
        } else if (i == 72) {
            run("touch", buildPath(base_dir, ".noautoformat"));
        } else {
            createUnformattedCpp(buildPath(base_dir, "file_" ~ i.to!string ~ ".cpp"));
        }
    }

    assert(autoformat("-r", ta.root).status == 0);
    assert(dirEntries(".", SpanMode.depth).filter!(a => a.baseName.endsWith(".orig")).count == 81);
}

void testSetup(const string root) {
    auto ta = TestArea(root);
    assert(autoformat("--setup").status == 0);
    assert(exists(buildPath(autoformatBinary.dirName, "autoformat_src")));
    assert(exists(buildPath(autoformatBinary.dirName, "autoformat_src.py")));
}

void testTrailingWhitespaceDetector(const string root) {
    auto ta = TestArea(root);
    createRepo;

    // the tool shall report no error
    assert(autoformat("--check-trailing-whitespace").status == 0);

    // the tool shall report no error because the file is not staged
    createTrailingWhitespaceFile("a.h");
    assert(autoformat("--check-trailing-whitespace").status == 0);

    // the tool shall report an error
    git("add", "a.h");
    assert(autoformat("--check-trailing-whitespace").status != 0);
}

void testNotMultipleMessageWhenToolNotInstalled(const string root) {
    auto ta = TestArea(root);
    createUnformattedPython("a.py");
    createUnformattedPython("b.py");

    // this test do not actually test what it should when autopep8 is NOT
    // installed.
    // "There shall be only one error message when the tool is not installed"
    // (must run single threaded)
    auto r = autoformat(debugMode ? "" : "-d", "a.py", "b.py");
    logger.info(r.output);
    assert(r.status == 0);
    auto m = r.output.matchAll(regex("executable file not found", "i"));
    assert(m.count <= 1);
}

void testDetab(const string root) {
    auto ta = TestArea(root);
    createTrailingWhitespaceFile("a.txt");

    auto r = autoformat(debugMode ? "" : "-d", "--tool-detab", "a.txt");
    logger.info(r.output);
    assert(r.status == 0);

    assert(exists("a.txt.orig"));
    auto content = std.file.readText("a.txt");
    logger.info(content);
    assert(content == "void f();\n");
}

void createRepo() {
    git("init", ".");
    run("touch", ".gitignore");
    git("add", ".gitignore");
    git("commit", "-am", "here be dragons");
}

string makeTmp(string root) {
    immutable base = "tmp_";
    int i = 0;
    string r;
    do {
        r = buildPath(root, base ~ i.to!string);
        ++i;
    }
    while (exists(r));

    logger.info("Temp area at: ", r);

    mkdir(r);

    return r;
}

struct TestArea {
    string root;
    const string parentCwd;

    @disable this();
    @disable this(this);

    this(string root) {
        this.parentCwd = getcwd;
        this.root = makeTmp(root.absolutePath);
        chdir(this.root);
    }

    ~this() {
        if (parentCwd.length != 0) {
            chdir(parentCwd);
        }
    }
}

auto git(T...)(T args_) {
    return run("git", args_);
}

auto autoformat(T...)(auto ref T args_) {
    if (debugMode) {
        return run(autoformatBinary, "-d", args_);
    }

    return run(autoformatBinary, args_);
}

auto run(T...)(string cmd, auto ref T args_) {
    string[] args;
    args ~= cmd;

    foreach (arg; args_) {
        if (arg.length != 0)
            args ~= arg;
    }

    logger.info(debugMode, "run: ", args.join(" "));
    auto r = execute(args);
    if (debugMode) {
        logger.info(r.output);
    } else if (r.status != 0) {
        logger.info(r.output);
    }

    return r;
}

void createSandboxFile(string content, string dst) {
    File(dst, "w").write(content);
}

immutable unformattedFileCpp = "   void f(int* x)\n{}\n";
alias createUnformattedCpp = dst => createSandboxFile(unformattedFileCpp, dst);

immutable unformattedFilePython = "def f(): \n return 1";
alias createUnformattedPython = dst => createSandboxFile(unformattedFilePython, dst);

immutable unformattedFileD = "   void f(int* x)\n{}\n";
alias createUnformattedD = dst => createSandboxFile(unformattedFileD, dst);

immutable trailingWhitespaceFile = "void f();   \n";
alias createTrailingWhitespaceFile = dst => createSandboxFile(trailingWhitespaceFile, dst);
