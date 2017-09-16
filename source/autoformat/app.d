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

import autoformat.formatter_tools;
import autoformat.git;
import autoformat.types;

immutable hookPreCommit = import("pre_commit");
immutable hookPrepareCommitMsg = import("prepare_commit_msg");
immutable gitConfigKey = "hooks.autoformat";

/// Active modes depending on the flags passed by the user.
enum Mode {
    /// Normal mode which is one or more files from command line
    normal,
    /// Print help and exit
    helpAndExit,
    /// Create the symlinks to emulate the old autoformatter written in python
    setup,
    /// Install git hooks
    installGitHook,
    /// Check staged files for trailing whitespace
    checkGitTrailingWhitespace,
}

/// The mode used to collect the files to process.
enum FileMode {
    /// Normal mode which is one or more files from command line
    normal,
    /// File list from stdin but processed as normal
    normalFileListFromStdin,
    /// Process recursively
    recursive,
}

/// The procedure to use to process files.
enum ToolMode {
    /// Normal mode which is one or more files from command line
    normal,
    /// Whitespace checker and fixup
    detabTool,
}

struct Config {
    Flag!"debugMode" debug_;
    Flag!"dryRun" dryRun;
    string installHook;
    Flag!"backup" backup;

    Mode mode;
    ToolMode formatMode;
    FileMode fileMode;
    string[] rawFiles;
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

    parseArgs(args, conf, help_info);

    try {
        confLogger(conf.debug_);
    }
    catch (Exception ex) {
        errorLog("Unable to configure internal logger");
        errorLog(ex.msg);
        return -1;
    }

    final switch (conf.mode) {
    case Mode.helpAndExit:
        printHelp(args[0], help_info);
        return -1;
    case Mode.setup:
        try {
            return setup(args);
        }
        catch (Exception ex) {
            errorLog("Unable to perform the setup");
            errorLog(ex.msg);
            return -1;
        }
    case Mode.installGitHook:
        string path_to_binary;
        try {
            path_to_binary = std.file.readLink("/proc/self/exe");
        }
        catch (Exception ex) {
            errorLog(
                    "Unable to read the symlink '/proc/self/exe'. Using args[0] instead, " ~ args[0]);
            path_to_binary = args[0];
        }
        try {
            return installGitHook(AbsolutePath(conf.installHook), path_to_binary);
        }
        catch (Exception ex) {
            errorLog("Unable to install the git hook");
            errorLog(ex.msg);
            return -1;
        }
    case Mode.checkGitTrailingWhitespace:
        import autoformat.tool_whitespace_check;

        FormatterResult res = runWhitespaceCheck;
        if (res.status == FormatterStatus.unchanged) {
            return 0;
        } else if (res.status == FormatterStatus.failedWithUserMsg) {
            errorLog(res.msg);
        }
        return -1;
    case Mode.normal:
        return fileMode(conf);
    }
}

int fileMode(Config conf) nothrow {
    AbsolutePath[] files;

    final switch (conf.fileMode) {
    case FileMode.recursive:
        try {
            auto tmp = recursiveFileList(AbsolutePath(conf.rawFiles[0]));
            if (tmp.isNull)
                return -1;
            else
                files = tmp.get;
        }
        catch (Exception ex) {
            errorLog("Error during recursive processing of files");
            errorLog(ex.msg);
            return -1;
        }
        break;
    case FileMode.normalFileListFromStdin:
        try {
            files = filesFromStdin;
        }
        catch (Exception ex) {
            errorLog("Unable to read a list of files separated by newline from stdin");
            errorLog(ex.msg);
            return -1;
        }
        break;
    case FileMode.normal:
        files = conf.rawFiles.map!(a => AbsolutePath(a)).array();
        break;
    }

    return formatMode(conf, files);
}

int formatMode(Config conf, AbsolutePath[] files) nothrow {
    import std.typecons : tuple;

    const auto tconf = ToolConf(conf.dryRun, conf.backup);

    final switch (conf.formatMode) {
    case ToolMode.normal:
        FormatterStatus status;
        try {
            status = parallelRun!(oneFileRespectKind, OneFileRespectKindEntry)(files,
                    conf.debug_ ? PoolConf.debug_ : PoolConf.auto_, tconf);
            logger.trace(status);
        }
        catch (Exception ex) {
            errorLog("Failed to run");
            errorLog(ex.msg);
            return -1;
        }

        if (conf.dryRun) {
            return status.among(FormatterStatus.formattedOk, FormatterStatus.wouldChange) ? -1 : 0;
        } else {
            return status == FormatterStatus.error ? -1 : 0;
        }
    case ToolMode.detabTool:
        import autoformat.tool_detab;

        return 0;
    }
}

void parseArgs(ref string[] args, ref Config conf, ref GetoptResult help_info) nothrow {
    bool debug_, dryRun, noBackup, recursive, setup, stdin_, help, check_whitespace, tool_detab;

    try {
        // dfmt off
        help_info = getopt(args, std.getopt.config.keepEndOfOptions,
            "check-trailing-whitespace", "check files for trailing whitespace", &check_whitespace,
            "d|debug", "change loglevel to debug", &debug_,
            "i|install-hook", "install git hooks to autoformat during commit of added or modified files", &conf.installHook,
            "n|dry-run", "(ONLY supported by c, c++, java) perform a trial run with no changes made to the files. Exit status != 0 indicates a change would have occured if ran without --dry-run", &dryRun,
            "no-backup", "no backup file is created", &noBackup,
            "r|recursive", "autoformat recursive", &recursive,
            "stdin", "file list separated by newline read from", &stdin_,
            "setup", "finalize installation of autoformatter by creating symlinks", &setup,
            "tool-detab", "whitespace checker and fixup (all filetypes, respects .noautoformat)", &tool_detab,
            );
        // dfmt on
        conf.debug_ = cast(typeof(Config.debug_)) debug_;
        conf.dryRun = cast(typeof(Config.dryRun)) dryRun;
        conf.backup = cast(typeof(Config.backup)) !noBackup;
        help = help_info.helpWanted;

        logger.info(conf.debug_, "Debug mode activated");
    }
    catch (std.getopt.GetOptException ex) {
        errorLog(ex.msg);
        help = true;
    }
    catch (Exception ex) {
        errorLog(ex.msg);
        help = true;
    }

    // Main mode

    if (help) {
        conf.mode = Mode.helpAndExit;
    } else if (setup) {
        conf.mode = Mode.setup;
    } else if (conf.installHook.length != 0) {
        conf.mode = Mode.installGitHook;
    } else if (check_whitespace) {
        conf.mode = Mode.checkGitTrailingWhitespace;
    }

    if (conf.mode != Mode.normal) {
        // modes that do not require a specific FileMode
        return;
    }

    // File mode

    if (recursive) {
        conf.fileMode = FileMode.recursive;
    } else if (stdin_) {
        conf.fileMode = FileMode.normalFileListFromStdin;
    }

    if (args.length > 1)
        conf.rawFiles = args[1 .. $];

    if (conf.fileMode != FileMode.normalFileListFromStdin && args.length < 2) {
        errorLog("Wrong number of arguments, probably missing FILE(s)");
        conf.mode = Mode.helpAndExit;
        return;
    }

    // Tool mode

    if (tool_detab) {
        conf.formatMode = ToolMode.detabTool;
    }
}

void confLogger(Flag!"debugMode" debug_) {
    if (debug_) {
        logger.globalLogLevel = logger.LogLevel.all;
    } else {
        import autoformat.logger;

        logger.globalLogLevel = logger.LogLevel.info;
        logger.sharedLog = new CustomLogger(logger.LogLevel.info);
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

struct OneFileRespectKindEntry {
    Tuple!(ulong, "index", AbsolutePath, "value") f;
    alias f this;

    ToolConf conf;
}

alias ToolConf = Tuple!(Flag!"dryRun", "dryRun", Flag!"backup", "backup");

FormatterStatus oneFileRespectKind(OneFileRespectKindEntry f) nothrow {
    try {
        if (f.value.isDir || f.value.extension.length == 0) {
            return FormatterStatus.unchanged;
        }
    }
    catch (Exception ex) {
        return FormatterStatus.unchanged;
    }

    auto res = f.value.isOkToFormat;
    if (!res.ok) {
        try {
            logger.warningf("%s %s", f.index + 1, res.payload);
        }
        catch (Exception ex) {
            errorLog(ex.msg);
        }
        return FormatterStatus.unchanged;
    }

    auto rval = FormatterStatus.unchanged;

    try {
        rval = formatFile(AbsolutePath(f.value), f.conf.backup, f.conf.dryRun);
    }
    catch (Exception ex) {
        errorLog(ex.msg);
    }

    return rval;
}

enum PoolConf {
    debug_,
    auto_
}

FormatterStatus parallelRun(alias Func, ArgsT)(AbsolutePath[] files_, PoolConf poolc, ToolConf conf) {
    static FormatterStatus merge(FormatterStatus a, FormatterStatus b) {
        // when a is an error it can never change
        if (!b.among(FormatterStatus.formattedOk, FormatterStatus.unchanged)) {
            return b;
        } else if (b == FormatterStatus.formattedOk) {
            return b;
        } else {
            return a;
        }
    }

    // dfmt off
    auto files = files_
        .filter!(a => a.length > 0)
        .enumerate.map!(a => ArgsT(a, conf))
        .array();
    // dfmt on

    TaskPool pool;
    final switch (poolc) {
    case PoolConf.debug_:
        // zero because the main thread is also working which thus ensures that
        // only one thread in the pool exist for work. No parallelism.
        pool = new TaskPool(0);
        break;
    case PoolConf.auto_:
        pool = new TaskPool;
        break;
    }

    scope (exit)
        pool.stop;
    auto status = pool.reduce!merge(FormatterStatus.unchanged, std.algorithm.map!Func(files));
    pool.finish;

    return status;
}

Nullable!(AbsolutePath[]) recursiveFileList(AbsolutePath path) {
    typeof(return) rval;

    if (!path.isDir) {
        logger.errorf("not a directory: %s", path);
        return rval;
    }

    rval = dirEntries(path, SpanMode.depth).map!(a => AbsolutePath(a.name)).array();
    return rval;
}

FormatterStatus formatFile(AbsolutePath p, Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    FormatterStatus status;

    try {
        logger.tracef("%s (backup:%s dryRun:%s)", p, backup, dry_run);

        foreach (f; formatters) {
            if (f[0](p.extension)) {
                auto res = f[1](p, backup, dry_run);
                status = res;

                final switch (res.status) {
                case FormatterStatus.error:
                    goto case;
                case FormatterStatus.failedWithUserMsg:
                    logger.error(res.msg);
                    break;
                case FormatterStatus.unchanged:
                    break;
                case FormatterStatus.formattedOk:
                    goto case;
                case FormatterStatus.wouldChange:
                    logger.info("formatted ", p);
                    break;
                }

                break;
            }
        }
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

/**
 * Params:
 *  install_to = path to a director containing a .git-directory
 *  autoformat_bin = either an absolute or relative path to the autoformat binary
 */
int installGitHook(AbsolutePath install_to, string autoformat_bin) {
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
        writeln;
        writeln("   # check for trailing whitespace in all staged files");
        writeln("   # this can be used separately from the above autoformat");
        writeln("   git config --global hooks.autoformat-check-whitespace true");
        writeln;
        writeln("Recommendation:");
        writeln("   git config --global hooks.autoformat auto");
        writeln("   git config --global hooks.autoformat-check-whitespace true");
    }

    static void createHook(AbsolutePath hook_p, string msg) {
        auto f = File(hook_p, "w");
        f.write(msg);
        f.close;
        makeExecutable(hook_p);
    }

    static void injectHook(AbsolutePath p, string raw) {
        import std.utf;

        string s = format("$GIT_DIR/hooks/%s $@", raw);
        // remove the old hook so it doesn't collide. This will probably have
        // to stay until 2019.
        string remove = format("source $GIT_DIR/hooks/%s", raw);

        if (exists(p)) {
            auto content = File(p).byLine.appendUnique(s, remove).joiner("\n").text;
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
    createHook(AbsolutePath(git_auto_pre_commit), format(hookPreCommit, autoformat_bin));
    createHook(AbsolutePath(git_auto_pre_msg), format(hookPrepareCommitMsg, autoformat_bin));
    injectHook(AbsolutePath(git_pre_commit), git_auto_pre_commit.baseName);
    injectHook(AbsolutePath(git_pre_msg), git_auto_pre_msg.baseName);

    usage;

    return 0;
}

/// Append the string to the range if it doesn't exist.
auto appendUnique(T)(T r, string msg, string remove) if (isInputRange!T) {
    enum State {
        analyzing,
        found,
        append,
        finished
    }

    struct Result {
        string msg;
        string remove;
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
                } else if (r.front == remove) {
                    popFront;
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

    return Result(msg, remove, r);
}

@("shall append the message if it doesn't exist")
unittest {
    string msg = "append me";
    string remove = "remove me";

    string[] text_with_msg = "foo\nbar\nappend me\nfjump\nremove me\n".split("\n");
    string[] text_missing_msg = "foo\nremove me\nbar\nfjump\n".split("\n");

    {
        string[] result = text_with_msg.appendUnique(msg, remove).array();
        writeln(text_with_msg, result);
        assert(cmp(result, text_with_msg) == 0);
    }
    {
        string[] result = text_missing_msg.appendUnique(msg, remove).array();
        writeln(text_missing_msg, result);
        assert(cmp(result, text_missing_msg ~ [msg]) == 0);
    }
}

void makeExecutable(string path) {
    import core.sys.posix.sys.stat;

    setAttributes(path, getAttributes(path) | S_IRWXU);
}
