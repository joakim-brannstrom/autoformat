/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module autoformat.app;

import logger = std.experimental.logger;
import std.algorithm : map, filter, among, joiner, canFind;
import std.conv : text;
import std.exception : collectException;
import std.file : isDir, dirEntries, exists, symlink, setAttributes, getAttributes;
import std.format : format;
import std.getopt : GetoptResult, getopt, defaultGetoptPrinter;
import std.parallelism : TaskPool;
import std.path : extension, buildPath, expandTilde, baseName, absolutePath, dirName;
import std.range : enumerate, isInputRange;
import std.array : array, appender;
import std.regex : matchFirst, ctRegex;
import std.stdio : writeln, writefln, File, stdin;
import std.typecons : Tuple, Nullable, Flag;
import std.sumtype;

import colorlog;
import my.optional;

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
    /// Dump config
    dumpConfig,
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
    VerboseMode verbosity;
    Flag!"dryRun" dryRun;
    string installHook;
    Flag!"backup" backup;

    string[] rawFiles;

    Mode mode;
    FileMode fileMode;
    ToolMode formatMode;
    ConfigDumpCommand configDumpCommand;
    bool ignoreNoAutoformat;
}

int main(string[] args) nothrow {
    confLogger(VerboseMode.info).collectException;

    Config conf;
    GetoptResult help_info;

    parseArgs(args, conf, help_info);
    confLogger(conf.verbosity).collectException;

    final switch (conf.mode) {
    case Mode.helpAndExit:
        printHelp(args[0], help_info);
        return -1;
    case Mode.setup:
        try {
            return setup(args);
        } catch (Exception ex) {
            logger.error("Unable to perform the setup").collectException;
            logger.error(ex.msg).collectException;
            return 1;
        }
    case Mode.installGitHook:
        import std.file : thisExePath;

        string path_to_binary;
        try {
            path_to_binary = thisExePath;
        } catch (Exception ex) {
            logger.error("Unable to read the symlink '/proc/self/exe'. Using args[0] instead, " ~ args[0])
                .collectException;
            path_to_binary = args[0];
        }
        try {
            return installGitHook(AbsolutePath(conf.installHook), path_to_binary);
        } catch (Exception ex) {
            logger.error("Unable to install the git hook").collectException;
            logger.error(ex.msg).collectException;
            return 1;
        }
    case Mode.checkGitTrailingWhitespace:
        import autoformat.tool_whitespace_check;

        int returnCode;
        runWhitespaceCheck.match!((Unchanged a) {}, (FormattedOk a) {}, (WouldChange a) {
        }, (FailedWithUserMsg a) {
            logger.error(a.msg).collectException;
            returnCode = 1;
        }, (FormatError a) { returnCode = 1; });
        return returnCode;
    case Mode.normal:
        return fileMode(conf);
    case Mode.dumpConfig:
        return dumpConfigMode(conf);
    }
}

int fileMode(Config conf) nothrow {
    AbsolutePath[] files;

    final switch (conf.fileMode) {
    case FileMode.recursive:
        try {
            auto tmp = recursiveFileList(AbsolutePath(conf.rawFiles[0]));
            if (tmp.isNull)
                return 1;
            else
                files = tmp.get;
        } catch (Exception ex) {
            logger.error("Error during recursive processing of files").collectException;
            logger.error(ex.msg).collectException;
            return 1;
        }
        break;
    case FileMode.normalFileListFromStdin:
        try {
            files = filesFromStdin;
        } catch (Exception ex) {
            logger.error("Unable to read a list of files separated by newline from stdin")
                .collectException;
            logger.error(ex.msg).collectException;
            return 1;
        }
        break;
    case FileMode.normal:
        try {
            files = conf.rawFiles.map!(a => AbsolutePath(a)).array();
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            return 1;
        }
        break;
    }

    return formatMode(conf, files);
}

int formatMode(Config conf, AbsolutePath[] files) nothrow {
    import std.conv : to;
    import std.typecons : tuple;

    const auto tconf = ToolConf(conf.dryRun, conf.backup, conf.ignoreNoAutoformat);
    const auto pconf = conf.verbosity == VerboseMode.trace ? PoolConf.debug_ : PoolConf.auto_;
    FormatterResult result;

    final switch (conf.formatMode) {
    case ToolMode.normal:
        try {
            result = parallelRun!(oneFileRespectKind, OneFileConf)(files, pconf, tconf);
        } catch (Exception ex) {
            logger.error("Failed to run").collectException;
            logger.error(ex.msg).collectException;
        }
        break;

    case ToolMode.detabTool:
        import autoformat.tool_detab;

        static auto runDetab(OneFileConf f) nothrow {
            try {
                if (f.value.isDir) {
                    return FormatterResult(Unchanged.init);
                }
            } catch (Exception ex) {
                return FormatterResult(Unchanged.init);
            }

            static import autoformat.tool_detab;

            return autoformat.tool_detab.runDetab(f.value, f.conf.backup, f.conf.dryRun);
        }

        try {
            result = parallelRun!(runDetab, OneFileConf)(files, pconf, tconf);
        } catch (Exception ex) {
            logger.error("Failed to run").collectException;
            logger.error(ex.msg).collectException;
        }
        break;
    }

    int returnCode;
    if (conf.dryRun) {
        result.match!((Unchanged a) {}, (FormattedOk a) { returnCode = 1; }, (WouldChange a) {
            returnCode = 1;
        }, (FailedWithUserMsg a) {}, (FormatError a) {});
    } else {
        result.match!((Unchanged a) {}, (FormattedOk a) {}, (WouldChange a) {},
                (FailedWithUserMsg a) {}, (FormatError a) { returnCode = 1; });
    }

    return returnCode;
}

int dumpConfigMode(Config conf) nothrow {
    foreach (f; configurationDumpers) {
        try {
            if (f[0](conf.configDumpCommand))
                f[1]();
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    return 0;
}

void parseArgs(ref string[] args, ref Config conf, ref GetoptResult help_info) nothrow {
    import std.traits : EnumMembers;
    static import std.getopt;

    bool check_whitespace;
    bool dryRun;
    bool help;
    bool noBackup;
    bool recursive;
    bool setup;
    bool stdin_;
    bool tool_detab;

    try {
        // dfmt off
        help_info = getopt(args, std.getopt.config.keepEndOfOptions,
            "check-trailing-whitespace", "check files for trailing whitespace", &check_whitespace,
            "f|force", "force formatting of file by ignoring .noautoformat", &conf.ignoreNoAutoformat,
            "i|install-hook", "install git hooks to autoformat during commit of added or modified files", &conf.installHook,
            "no-backup", "no backup file is created", &noBackup,
            "n|dry-run", "(ONLY supported by c, c++, java) perform a trial run with no changes made to the files. Exit status != 0 indicates a change would have occured if ran without --dry-run", &dryRun,
            "r|recursive", "autoformat recursive", &recursive,
            "setup", "finalize installation of autoformatter by creating symlinks", &setup,
            "stdin", "file list separated by newline read from", &stdin_,
            "dump-config", format("dumps the config provided language. Supported (%-(%s, %))", [EnumMembers!ConfigDumpCommand].filter!(a => a != ConfigDumpCommand.noConfigDump)), &conf.configDumpCommand,
            "tool-detab", "whitespace checker and fixup (all filetypes, respects .noautoformat)", &tool_detab,
            "v|verbose", format("Set the verbosity (%-(%s, %))", [EnumMembers!(VerboseMode)]), &conf.verbosity,
            );
        // dfmt on
        conf.dryRun = cast(typeof(Config.dryRun)) dryRun;
        conf.backup = cast(typeof(Config.backup)) !noBackup;
        help = help_info.helpWanted;
    } catch (std.getopt.GetOptException ex) {
        logger.error(ex.msg).collectException;
        help = true;
    } catch (Exception ex) {
        logger.error(ex.msg).collectException;
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
    } else if (conf.configDumpCommand != ConfigDumpCommand.noConfigDump) {
        conf.mode = Mode.dumpConfig;
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
        logger.error("Wrong number of arguments, probably missing FILE(s)").collectException;
        conf.mode = Mode.helpAndExit;
        return;
    }

    // Tool mode

    if (tool_detab) {
        conf.formatMode = ToolMode.detabTool;
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

struct OneFileConf {
    Tuple!(ulong, "index", AbsolutePath, "value") f;
    alias f this;

    ToolConf conf;
}

alias ToolConf = Tuple!(Flag!"dryRun", "dryRun", Flag!"backup", "backup", bool, "ignoreSupressOfFormat");

FormatterResult oneFileRespectKind(OneFileConf f) nothrow {
    try {
        if (f.value.isDir || f.value.extension.length == 0) {
            return FormatterResult(Unchanged.init);
        }
    } catch (Exception ex) {
        return FormatterResult(Unchanged.init);
    }

    auto res = isOkToFormat(f.value);
    if (f.conf.ignoreSupressOfFormat && !res.ok) {
        // ignore the magic supress file.
    } else if (!res.ok) {
        try {
            logger.warningf("%s %s", f.index + 1, res.payload);
        } catch (Exception ex) {
            logger.error(ex.msg).collectException;
        }
        return FormatterResult(Unchanged.init);
    }

    auto rval = FormatterResult(Unchanged.init);

    try {
        rval = formatFile(AbsolutePath(f.value), f.conf.backup, f.conf.dryRun);
    } catch (Exception ex) {
        logger.error(ex.msg).collectException;
    }

    return rval;
}

enum PoolConf {
    debug_,
    auto_
}

FormatterResult parallelRun(alias Func, ArgsT)(AbsolutePath[] files_, PoolConf poolc, ToolConf conf) {
    static FormatterResult merge(FormatterResult a, FormatterResult b) {
        auto rval = a;

        // if a is an error then let it propagate
        a.match!((Unchanged a) { rval = b; }, (FormattedOk a) { rval = b; }, (WouldChange a) {
        }, (FailedWithUserMsg a) {}, (FormatError a) {});

        // if b is unchanged then let the previous value propagate
        b.match!((Unchanged a) { rval = a; }, (FormattedOk a) {}, (WouldChange a) {
        }, (FailedWithUserMsg a) {}, (FormatError a) {});

        return rval;
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

    static import std.algorithm;

    scope (exit)
        pool.stop;
    auto status = pool.reduce!merge(FormatterResult(Unchanged.init),
            std.algorithm.map!Func(files));
    pool.finish;

    return status;
}

Nullable!(AbsolutePath[]) recursiveFileList(AbsolutePath path) {
    static import std.file;

    typeof(return) rval;

    if (!path.isDir) {
        logger.errorf("not a directory: %s", path);
        return rval;
    }

    rval = dirEntries(path, std.file.SpanMode.depth).map!(a => AbsolutePath(a.name)).array();
    return rval;
}

FormatterResult formatFile(AbsolutePath p, Flag!"backup" backup, Flag!"dryRun" dry_run) nothrow {
    FormatterResult status;

    try {
        logger.tracef("%s (backup:%s dryRun:%s)", p, backup, dry_run);

        foreach (f; formatters) {
            if (f[0](p.extension)) {
                auto res = f[1](p, backup, dry_run);
                status = res;

                res.match!((Unchanged a) {}, (FormattedOk a) {
                    logger.info("formatted ", p);
                }, (WouldChange a) { logger.info("formatted (dryrun) ", p); }, (FailedWithUserMsg a) {
                    logger.error(a.msg);
                }, (FormatError a) { logger.error("unable to format ", p); });
                break;
            }
        }
    } catch (Exception ex) {
        logger.error("Unable to format file: " ~ p).collectException;
        logger.error(ex.msg).collectException;
    }

    return status;
}

void printHelp(string arg0, ref GetoptResult help_info) nothrow {
    import std.format : format;

    try {
        defaultGetoptPrinter(format(`Tool to format [c, c++, java, d, rust] source code
Usage: %s [options] PATH`, arg0), help_info.options);
    } catch (Exception ex) {
        logger.error("Unable to print command line interface help information to stdout")
            .collectException;
        logger.error(ex.msg).collectException;
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
        if (gitConfigValue(gitConfigKey).orElse(string.init).among("auto", "warn", "interrupt")) {
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

        // remove the old hook so it doesn't collide.
        // v1: This will probably have to stay until late 2019.
        string v1 = format("source $GIT_DIR/hooks/%s", raw);
        // v2: Stay until late 2020
        string v2 = format("$GIT_DIR/hooks/%s $@", raw);
        string latest = format("$(git rev-parse --git-dir)/hooks/%s $@", raw);

        if (exists(p)) {
            auto content = File(p).byLine.appendUnique(latest, [v1, v2, latest]).joiner("\n").text;
            auto f = File(p, "w");
            f.writeln(content);
        } else {
            auto f = File(p, "w");
            f.writeln("#!/bin/bash");
            f.writeln(latest);
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
            hook_dir = p.orElse(AbsolutePath.init);
        } else {
            logger.error("Unable to locate a git hook directory at: ", install_to);
            return 1;
        }
    }

    import autoformat.format_c_cpp : clangToolEnvKey, getClangFormatterTool;

    auto git_pre_commit = buildPath(hook_dir, "pre-commit");
    auto git_pre_msg = buildPath(hook_dir, "prepare-commit-msg");
    auto git_auto_pre_commit = buildPath(hook_dir, "autoformat_pre-commit");
    auto git_auto_pre_msg = buildPath(hook_dir, "autoformat_prepare-commit-msg");
    logger.info("Installing git hooks to: ", install_to);
    createHook(AbsolutePath(git_auto_pre_commit), format(hookPreCommit,
            autoformat_bin, clangToolEnvKey, getClangFormatterTool));
    createHook(AbsolutePath(git_auto_pre_msg), format(hookPrepareCommitMsg, autoformat_bin));
    injectHook(AbsolutePath(git_pre_commit), git_auto_pre_commit.baseName);
    injectHook(AbsolutePath(git_pre_msg), git_auto_pre_msg.baseName);

    usage;

    return 0;
}

/// Append the string to the range if it doesn't exist.
auto appendUnique(T)(T r, string msg, string[] remove) if (isInputRange!T) {
    enum State {
        analyzing,
        found,
        append,
        finished
    }

    struct Result {
        string msg;
        string[] remove;
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
                } else if (canFind(remove, r.front)) {
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
