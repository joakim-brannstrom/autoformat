#!/bin/bash

set -e

if [[ ! -d tools ]]; then
    git clone --depth 1 -b integration-test-tools https://github.com/joakim-brannstrom/autoformat.git tools
fi

export PATH=$PWD/tools/bin:$PATH

echo "Test information"
echo $PATH
which dfmt
which astyle
which clang-format

dub test && dub run -c integration_test
