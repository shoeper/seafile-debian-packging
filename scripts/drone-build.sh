#!/bin/bash

set -e -x

SCRIPT=$(readlink -f "$0")
TOPDIR=$(dirname "${SCRIPT}")/..

if [[ $DRONE_COMMIT_BRANCH == lpad* ]]; then
    # Release builds.
    exec $TOPDIR/scripts/build-debs.sh
fi
