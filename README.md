# autoformat [![Build Status](https://dev.azure.com/wikodes/wikodes/_apis/build/status/joakim-brannstrom.autoformat?branchName=master)](https://dev.azure.com/wikodes/wikodes/_build/latest?definitionId=6&branchName=master)

Wraps existing tools for formatting of source code in a handy package with integration with git.

# Getting Started

autoformat depend on the following packages:

 * [D compiler](https://dlang.org/download.html) (dmd 2.079+, ldc 1.11.0+)

Optional:
 * astyle
 * clang-format
 * dfmt

It is recommended to install the D compiler by downloading it from the official distribution page.
```sh
# link https://dlang.org/download.html
curl -fsS https://dlang.org/install.sh | bash -s dmd
```

For users running Ubuntu some of the dependencies can be installed with apt.
```sh
sudo apt install astyle clang-format
```

The easiest way to now run autoformat is by using dub:
```sh
dub run autoformat
```

Otherwise you can clone the repo, build and install manually.
```sh
git clone https://github.com/joakim-brannstrom/autoformat.git
cd autoformat
dub build -b release
```
Copy the files from autoformat/build to wherever you want them

Done! Have fun.
Don't be shy to report any issue that you find.

# Git Integration

It couldn't be easier. Make sure that autoformat is in your PATH.

To install the git hooks:
```sh
autoformat -i path/to/directory/with/a/.git
```

When the hook is being installed it will prompt for one of three options.
Choose the configuration you like.

Now whenever you do a _git commit_ it will check/format the changed files.
