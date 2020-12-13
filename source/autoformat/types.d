/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module autoformat.types;

import sumtype;
public import my.path : Path, AbsolutePath;

enum FormatterStatus {
    /// failed to format or some other kind of error
    error,
    /// error when formatting with an error msg
    failedWithUserMsg,
    ///
    unchanged,
    /// formatted file with no errors
    formattedOk,
    /// The file would change if it where autoformatted
    wouldChange,
}

struct FormatterResult {
    FormatterStatus status;
    string msg;

    alias status this;
}
