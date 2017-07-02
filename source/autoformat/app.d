/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module autoformat.app;

import std.algorithm;
import std.conv : text;
import std.exception;
import std.file;
import std.format;
import std.getopt;
import std.parallelism;
import std.path;
import std.process;
import std.range;
import std.regex : matchFirst, ctRegex;
import std.stdio;
import std.typecons;
import std.variant;

import logger = std.experimental.logger;

import autoformat.git;
import autoformat.types;

immutable hookPreCommit = import("pre_commit");
immutable hookPrepareCommitMsg = import("prepare_commit_msg");
immutable gitConfigKey = "hooks.autoformat";
immutable astyleConfRaw = import("astyle.conf");
string[] astyleConf;

enum FormatterStatus {
    /// failed autoformatting or some other kind of error
    error,
    /// autoformatting done and it went okey
    ok,
    /// The file would change if it where autoformatted
    wouldChange,
}

struct Config {
    bool debug_;
    bool dryRun;
    bool help = false;
    string installHook;
    bool noBackup;
    bool recursive;
    bool setup;
    bool stdin;
}

void internalLog(logger.LogLevel lvl, int line = __LINE__, string file = __FILE__, string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__, string moduleName = __MODULE__, T...)(
        lazy string msg, lazy T args) nothrow {
    try {
        logger.logf!(line, file, funcName, prettyFuncName, moduleName)(lvl, msg, args);
    }
    catch (Exception ex) {
    }
}

alias infoLog(T...) = internalLog!(logger.LogLevel.info, T);
alias traceLog(T...) = internalLog!(logger.LogLevel.trace, T);
alias errorLog(T...) = internalLog!(logger.LogLevel.error, T);

int main(string[] args) nothrow {
    Config conf;
    GetoptResult help_info;

    .astyleConf = astyleConfRaw.splitter("\n").filter!(a => a.length > 0).array();

    try {
        // dfmt off
        help_info = getopt(args, std.getopt.config.keepEndOfOptions,
            "stdin", "file read from stdin separated by linebreak", &conf.stdin,
            "d|debug", "change loglevel to debug", &conf.debug_,
            "n|dry-run", "perform a trial run with no changes made to the files. Exit status != 0 indicates a change would have occured if ran without --dry-run", &conf.dryRun,
            "no-backup", "no backup file is created", &conf.noBackup,
            "r|recursive", "autoformat recursive", &conf.recursive,
            "i|install-hook", "install git hooks to autoformat during commit of added or modified files", &conf.installHook,
            "setup", "finalize installation of autoformatter by creating symlinks", &conf.setup,
            );
        // dfmt on
        conf.help = help_info.helpWanted;
    }
    catch (std.getopt.GetOptException ex) {
        errorLog(ex.msg);
        conf.help = true;
    }
    catch (Exception ex) {
        errorLog(ex.msg);
        conf.help = true;
    }

    try {
        if (conf.debug_) {
            logger.globalLogLevel = logger.LogLevel.all;
        } else {
            logger.globalLogLevel = logger.LogLevel.info;
            logger.sharedLog = new MyCustomLogger(logger.LogLevel.info);
        }
    }
    catch (Exception ex) {
        errorLog("Unable to configure internal logger");
        errorLog(ex.msg);
        return -1;
    }

    if (conf.help) {
        printHelp(args[0], help_info);
        return -1;
    } else if (conf.setup) {
        try {
            return setup(args);
        }
        catch (Exception ex) {
            errorLog("Unable to perform the setup");
            errorLog(ex.msg);
            return -1;
        }
    } else if (conf.installHook.length != 0) {
        try {
            return installGitHook(AbsolutePath(conf.installHook));
        }
        catch (Exception ex) {
            errorLog("Unable to install the git hook");
            errorLog(ex.msg);
            return -1;
        }
    }

    if (conf.stdin) {
        try {
            auto files = filesFromStdin;
            return run(files, cast(Flag!"backup") !conf.noBackup,
                    cast(Flag!"dryRun") conf.dryRun);
        }
        catch (Exception ex) {
            errorLog("Unable to read a list of files separated by newline from stdin");
            errorLog(ex.msg);
            return -1;
        }
    } else if (args.length != 2) {
        printHelp(args[0], help_info);
        errorLog("Wrong number of arguments, probably missing the PATH");
        return -1;
    }

    if (conf.recursive) {
        try {
            return runRecursive(AbsolutePath(args[1]),
                    cast(Flag!"backup") !conf.noBackup, cast(Flag!"dryRun") conf.dryRun);
        }
        catch (Exception ex) {
            errorLog("Error during recursive processing of files");
            errorLog(ex.msg);
            return -1;
        }
    } else {
        AbsolutePath p;
        try {
            p = AbsolutePath(args[1]);
        }
        catch (Exception ex) {
            errorLog("Unable to transform to an absolute path: " ~ args[1]);
            errorLog(ex.msg);
            return -1;
        }

        return run(p, cast(Flag!"backup") !conf.noBackup, cast(Flag!"dryRun") conf.dryRun);
    }
}

AbsolutePath[] filesFromStdin() {
    import std.string : strip;

    auto r = appender!(AbsolutePath[])();

    char[] line;
    while (stdin.readln(line)) {
        r.put(AbsolutePath(line.strip.idup));
    }

    return r.data;
}

int run(AbsolutePath[] files_, Flag!"backup" backup, Flag!"dryRun" dry_run) {
    static FormatterStatus merge(FormatterStatus a, FormatterStatus b) {
        // when a is an error it can never change
        if (a != FormatterStatus.ok) {
            return a;
        } else {
            return b;
        }
    }

    static FormatterStatus oneFile(T)(T f) {
        if (f.value.isDir) {
            return FormatterStatus.ok;
        }

        auto res = f.value.isOkToFormat;
        if (!res.ok) {
            logger.errorf(" %s\t%s", f.index + 1, res.payload);
            return FormatterStatus.ok;
        }

        logger.infof("  %s\t%s", f.index + 1, f.value);
        auto resf = formatFile(AbsolutePath(f.value), f.backup, f.dryRun, (string a) {
            logger.error(a);
        });

        return resf;
    }

    static struct Entry(T) {
        Flag!"backup" backup;
        Flag!"dryRun" dryRun;
        T payload;
        alias payload this;
    }

    auto files = files_.enumerate.map!(a => Entry!(typeof(a))(backup, dry_run, a)).array();

    auto pool = new TaskPool;
    logger.info("Formatting files");
    auto status = pool.reduce!merge(FormatterStatus.ok, std.algorithm.map!oneFile(files));
    pool.finish;

    logger.trace(status);
    return status == FormatterStatus.ok ? 0 : -1;
}

int runRecursive(AbsolutePath path, Flag!"backup" backup, Flag!"dryRun" dry_run) {
    if (!path.isDir) {
        logger.errorf("not a directory: %s", path);
        return FormatterStatus.error;
    }

    auto files = dirEntries(path, SpanMode.depth).map!(a => AbsolutePath(a.name)).array();

    return run(files, backup, dry_run);
}

int run(AbsolutePath path, Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    auto status = FormatterStatus.ok;

    auto res = path.isOkToFormat;
    if (!res.ok) {
        errorLog(res.payload);
        return 1;
    }

    status = formatFile(path, backup, dry_run, (string a) { logger.error(a); });

    internalLog!(logger.LogLevel.info)("%", status);
    return status == FormatterStatus.ok ? 0 : -1;
}

alias FormatterResult = Algebraic!(string, FormatterStatus);
alias FormatterFunc = FormatterResult function(AbsolutePath p,
        Flag!"backup" backup, Flag!"dryRun" dry_run);
alias FormatterCheckFunc = bool function(string p);
alias Formatter = Tuple!(FormatterCheckFunc, FormatterFunc);

// dfmt off
enum formatters = [
    Formatter(&isC_CppFiletype, &runAstyle),
    Formatter(&isJavaFiletype, &runAstyle),
    Formatter(&isDFiletype, &runDfmt)
];
// dfmt on

FormatterStatus formatFile(T)(AbsolutePath p, Flag!"backup" backup,
        Flag!"dryRun" dry_run, T msgFunc) nothrow {
    FormatterStatus status;

    try {
        logger.tracef("%s (backup:%s dryRun:%s)", p, backup, dry_run);

        foreach (f; formatters) {
            if (f[0](p.extension)) {
                auto res = f[1](p, backup, dry_run);
                if (res.peek!string !is null) {
                    msgFunc(res.get!string());
                    status = FormatterStatus.error;
                    break;
                } else if (res.peek!FormatterStatus !is null) {
                    status = res.get!FormatterStatus;
                    break;
                }
            }
        }

        logger.trace(status);
    }
    catch (Exception ex) {
        errorLog("Unable to format file: " ~ p);
        errorLog(ex.msg);
    }

    return status;
}

void printHelp(string arg0, ref GetoptResult help_info) nothrow {
    import std.format : format;

    try {
        defaultGetoptPrinter(format(`Tool to format [c, c++, java] source code
Usage: %s [options] PATH`,
                arg0), help_info.options);
    }
    catch (Exception ex) {
        errorLog("Unable to print command line interface help information to stdout");
        errorLog(ex.msg);
    }
}

int setup(string[] args) {
    immutable arg0 = args[0];
    immutable original = arg0.expandTilde.absolutePath;
    immutable base = original.dirName;
    immutable backward_compatible_py0 = buildPath(base, "autoformat_src.py");
    immutable backward_compatible_py1 = buildPath(base, "autoformat_src");

    foreach (p; [backward_compatible_py0, backward_compatible_py1].filter!(a => !exists(a))) {
        symlink(original, p);
    }

    return 0;
}

int installGitHook(AbsolutePath install_to) {
    static void usage() {
        if (gitConfigValue(gitConfigKey).among("auto", "warn", "interrupt")) {
            return;
        }

        writeln("Activate hooks by configuring git");
        writeln("   # autoformat all changed files during commit");
        writeln("   git config --global hooks.autoformat auto");
        writeln("   # Warn if a file doesn't follow code standard during commit");
        writeln("   git config --global hooks.autoformat warn");
        writeln("   # Interrupt commit if a file doesn't follow code standard during commit");
        writeln("   git config --global hooks.autoformat interrupt");
    }

    static void createHook(AbsolutePath hook_p, string msg) {
        auto f = File(hook_p, "w");
        f.write(msg);
    }

    static void injectHook(AbsolutePath p, string raw) {
        import std.utf;

        string s = format("source $GIT_DIR/hooks/%s", raw);

        if (exists(p)) {
            auto content = File(p).byLine.appendUnique(s).joiner("\n").text;
            auto f = File(p, "w");
            f.writeln(content);
        } else {
            auto f = File(p, "w");
            f.writeln("#!/bin/bash");
            f.writeln(s);
            f.close;
        }
        makeExecutable(p);
    }

    { // sanity check
        if (!exists(install_to)) {
            writefln("Unable to install to %s, it doesn't exist", install_to);
            return 1;
        } else if (!isGitRoot(install_to)) {
            writefln("%s is not a git repo (no .git directory found)", install_to);
        }
    }

    AbsolutePath hook_dir;
    {
        auto p = gitHookPath(install_to);
        if (p.hasValue) {
            hook_dir = p.get!AbsolutePath;
        } else {
            logger.error("Unable to locate a git hook directory at: ", install_to);
            return -1;
        }
    }

    auto git_pre_commit = buildPath(hook_dir, "pre-commit");
    auto git_pre_msg = buildPath(hook_dir, "prepare-commit-msg");
    auto git_auto_pre_commit = buildPath(hook_dir, "autoformat_pre-commit");
    auto git_auto_pre_msg = buildPath(hook_dir, "autoformat_prepare-commit-msg");
    logger.info("Installing git hooks to: ", install_to);
    createHook(AbsolutePath(git_auto_pre_commit), hookPreCommit);
    createHook(AbsolutePath(git_auto_pre_msg), hookPrepareCommitMsg);
    injectHook(AbsolutePath(git_pre_commit), git_auto_pre_commit.baseName);
    injectHook(AbsolutePath(git_pre_msg), git_auto_pre_msg.baseName);

    usage;

    return 0;
}

/// Append the string to the range if it doesn't exist.
auto appendUnique(T)(T r, string msg) if (isInputRange!T) {
    enum State {
        analyzing,
        found,
        append,
        finished
    }

    struct Result {
        string msg;
        T r;
        State st;

        string front() {
            assert(!empty, "Can't get front of an empty range");

            if (st == State.append) {
                return msg;
            }

            static if (is(typeof(r.front) == char[])) {
                return r.front.idup;
            } else {
                return r.front;
            }
        }

        void popFront() {
            assert(!empty, "Can't pop front of an empty range");
            if (st == State.analyzing) {
                r.popFront;
                if (r.empty) {
                    st = State.append;
                } else if (r.front == msg) {
                    st = State.found;
                }
            } else if (st == State.found) {
                r.popFront;
            } else if (st == State.append) {
                st = State.finished;
            }
        }

        bool empty() {
            if (st.among(State.analyzing, State.found)) {
                return r.empty;
            } else if (st == State.append) {
                return false;
            } else {
                return true;
            }
        }
    }

    return Result(msg, r);
}

@("shall append the message if it doesn't exist")
unittest {
    string msg = "append me";

    string[] text_with_msg = "foo\nbar\nappend me\nfjump\n".split("\n");
    string[] text_missing_msg = "foo\nbar\nfjump\n".split("\n");

    {
        string[] result = text_with_msg.appendUnique(msg).array();
        writeln(text_with_msg, result);
        assert(cmp(result, text_with_msg) == 0);
    }
    {
        string[] result = text_missing_msg.appendUnique(msg).array();
        writeln(text_missing_msg, result);
        assert(cmp(result, text_missing_msg ~ [msg]) == 0);
    }
}

void makeExecutable(string path) {
    import core.sys.posix.sys.stat;

    setAttributes(path, getAttributes(path) | S_IRWXU);
}

auto runAstyle(AbsolutePath fname, Flag!"backup" backup, Flag!"dryRun" dry_run) {
    enum re_formatted = ctRegex!(`^\s*formatted.*`, "i");
    auto opts = astyleConf;

    if (backup) {
        opts ~= "--suffix=.orig";
    } else {
        opts ~= "--suffix=none";
    }

    if (dry_run) {
        opts ~= "--dry-run";
    }

    auto rval = FormatterResult(FormatterStatus.error);

    try {
        auto arg = ["astyle"] ~ opts ~ [cast(string) fname];
        logger.trace(arg.join(" "));
        auto res = execute(arg);
        logger.trace(res.output);

        if (dry_run && matchFirst(res.output, re_formatted)) {
            rval = FormatterResult(FormatterStatus.wouldChange);
        } else {
            rval = FormatterStatus.ok;
        }
    }
    catch (ErrnoException ex) {
        rval = FormatterResult(ex.msg);
    }

    return rval;
}

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

enum filetypeCheckers = [&isC_CppFiletype, &isDFiletype, &isJavaFiletype];

bool isFiletypeSupported(AbsolutePath p) nothrow {
    foreach (f; filetypeCheckers) {
        if (f(p.extension)) {
            return true;
        }
    }

    return false;
}

bool isC_CppFiletype(string p) nothrow {
    return p.among(".c", ".cpp", ".cxx", ".h", ".hpp") != 0;
}

bool isDFiletype(string p) nothrow {
    return p.among(".d", "di") != 0;
}

bool isJavaFiletype(string p) nothrow {
    return p.among(".java") != 0;
}

auto isOkToFormat(AbsolutePath p) nothrow {
    struct Result {
        string payload;
        bool ok;
    }

    Result res;

    if (!exists(p)) {
        res = Result("file not found: " ~ p);
    } else if (!isFiletypeSupported(p)) {
        res = Result("filetype not supported: " ~ p);
    } else {
        string w = p;
        while (w != "/") {
            if (exists(buildPath(w, "matlab.xml"))) {
                res = Result("matlab generated code");
                break;
            }

            try {
                auto a = AbsolutePath(w);
                if (isGitRoot(a)) {
                    break;
                }
            }
            catch (Exception ex) {
            }

            w = dirName(w);
        }
    }

    return Result(null, true);
}

class MyCustomLogger : logger.Logger {
    import std.experimental.logger;

    this(LogLevel lv) @safe {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        stderr.writefln("%s: %s", payload.logLevel, payload.msg);
    }
}
