/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module autoformat.types;

import sumtype;
public import my.path : Path, AbsolutePath;

/// failed to format or some other kind of error
struct FormatError {
    string msg;
}

/// error when formatting with an error msg
struct FailedWithUserMsg {
    string msg;
}

struct Unchanged {
}

/// formatted file with no errors
struct FormattedOk {
}

/// The file would change if it where autoformatted
struct WouldChange {
}

alias FormatterResult = SumType!(FormatError, FailedWithUserMsg, Unchanged,
        FormattedOk, WouldChange);
