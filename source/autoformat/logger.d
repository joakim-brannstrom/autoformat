/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module autoformat.logger;

import logger = std.experimental.logger;

class CustomLogger : logger.Logger {
    import std.algorithm : among;
    import std.stdio : stdout, stderr;
    import std.experimental.logger;

    this(LogLevel lv) @safe {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        auto out_ = stderr;

        if (payload.logLevel.among(LogLevel.info, LogLevel.trace)) {
            out_ = stdout;
        }

        string tabs = "\t";
        switch (payload.logLevel) {
        case LogLevel.trace:
            tabs = "\t\t";
            break;
        case LogLevel.info:
            tabs = "\t\t";
            break;
        default:
        }

        out_.writefln("%s: " ~ tabs ~ "%s", payload.logLevel, payload.msg);
    }
}
