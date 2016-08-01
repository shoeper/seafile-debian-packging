#!/bin/bash

set -x -e
set -o pipefail

topdir=/app
outputdir=/app/debs
branch=lpad

mkdir -p $outputdir

rm -f $outputdir/*.deb

cd $topdir

projects=(
    libsearpc
    ccnet
    seafile
    seafile-client
)

# Build 32 bit package with pbuilder
BUILDRESULT=/var/cache/pbuilder/debian-wheezy-i386/result/
for project in ${projects[*]}; do
    builddir=/tmp/build32-${project}
    rm -rf $builddir
    mkdir -p $builddir && cd $builddir
    git clone --branch ${branch} --depth 1 https://github.com/haiwen/${project}.git
    cd $project

    echo '3.0 (native)' > debian/source/format
    OS=debian DIST=wheezy ARCH=i386 pdebuild

    cd $BUILDRESULT
    # apt-ftparchive packages . > ./Packages
    cp *.deb $outputdir
done

# Build 64bit packages directly inside the container
for project in ${projects[*]}; do
    builddir=/tmp/build-${project}
    rm -rf $builddir
    mkdir -p $builddir && cd $builddir
    git clone --branch ${branch} --depth 1 https://github.com/haiwen/${project}.git
    cd $project
    dpkg-buildpackage -b

    cd $builddir
    # Install the debs because it would be required by latter projects (e.g. ccnet requires libsearpc pkgs.)
    dpkg -i ./*.deb
    cp ./*.deb $outputdir
done

if [[ $TRAVIS_PULL_REQUEST != "false" ]]; then
    echo "Not uploading for pull requests."
    exit 0
fi

if [[ $TRAVIS_TAG == "" && $TRAVIS_BRANCH != "lpad" ]]; then
    echo "TRAVIS_TAG not set, skipping upload. To force a build, push to the \"lpad\" branch."
    exit 0
fi

for pkg in $outputdir/*.deb; do
    /app/scripts/bintray-upload-deb $pkg
done
