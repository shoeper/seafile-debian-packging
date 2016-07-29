#!/bin/bash

set -x -e

topdir=/app
outputdir=/app/debs

mkdir -p $outputdir

rm -f $outputdir/*.deb

cd $topdir

projects=(
    libsearpc
    ccnet
    seafile
    seafile-client
)

for project in ${projects[*]}; do
    builddir=/tmp/build-${project}
    mkdir -p $builddir && cd $builddir
    git clone --branch lpad --depth 1 https://github.com/haiwen/${project}.git
    cd $project
    dpkg-buildpackage -b

    cd $builddir
    # Install the debs because it would be required by latter proejcts (e.g. ccnet requires libsearpc pkgs.)
    dpkg -i ./*.deb
    cp ./*.deb $outputdir
done

if [[ $TRAVIS_TAG == "" ]]; then
    echo "TRAVIS_TAG not set, skipping upload."
    exit 0
fi

for pkg in $outputdir/*.deb; do
    /app/scripts/bintray-upload-deb $pkg
done
