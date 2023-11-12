/**
Copyright: Copyright (c) Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module autoformat.common;

auto loggedExecute(string[] args) {
    import logger = std.experimental.logger;
    import std.process : execute;

    logger.tracef("%(%s %)", args);
    auto res = execute(args);
    logger.trace(res.output);
    return res;
}
