# autoformat

[![Build Status](https://travis-ci.org/joakim-brannstrom/autoformat.svg?branch=master)](https://travis-ci.org/joakim-brannstrom/autoformat)

Wraps existing tools for formatting of source code in a handy package with integration with git.

# Getting Started

autoformat depend on the following packages:
 * [D compiler](https://dlang.org/download.html) (dmd 2.072+, ldc 1.1.0+)

Optional:
 * astyle
 * dfmt

Download the D compiler of your choice, extract it and add to your PATH shell
variable.
```sh
# example with an extracted DMD
export PATH=/path/to/dmd/linux/bin64/:$PATH
```

Once the dependencies are installed it is time to download the source code and
build the binaries.
```sh
cd autoformat
dub build
```

Done!
Copy the files from autoformat/build to wherever you want them

# Git Integration

It couldn't be easier. Make sure that autoformat is in your PATH.

To install the git hooks:
```sh
autoformat -i path/to/directory/with/a/.git
```

When the hook is being installed it will prompt for one of three options.
Choose the configuration you like.

Now whenever you do a _git commit_ it will check/format the changed files.

# TODO

 * Integrate clang-format.
