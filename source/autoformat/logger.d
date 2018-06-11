/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module autoformat.logger;

import std.algorithm : among;
import std.stdio : writeln, writefln, stderr, stdout;
import logger = std.experimental.logger;
import std.experimental.logger : LogLevel;

class SimpleLogger : logger.Logger {
    this(LogLevel lv) @safe {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        auto out_ = stderr;

        if (payload.logLevel.among(LogLevel.info, LogLevel.trace)) {
            out_ = stdout;
        }

        out_.writefln("%s: %s", payload.logLevel, payload.msg);
    }
}

class DebugLogger : logger.Logger {
    this(const logger.LogLevel lv) {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        auto out_ = stderr;

        if (payload.logLevel.among(LogLevel.info, LogLevel.trace)) {
            out_ = stdout;
        }

        out_.writefln("%s: %s [%s:%d]", payload.logLevel, payload.msg,
                payload.funcName, payload.line);
    }
}
