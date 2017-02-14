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

declare -a __atexit_cmds

# Helper for eval'ing commands.
__atexit() {
    for cmd in "${__atexit_cmds[@]}"; do
        eval ${cmd}
    done
}

# Usage: atexit command arg1 arg2 arg3
atexit() {
    # Determine the current number of commands.
    local length=${#__atexit_cmds[*]}

    # Add this command to the end.
    __atexit_cmds[${length}]="${*}"

    # Set the trap handler if this was the first command added.
    if [[ ${length} -eq 0 ]]; then
        trap __atexit EXIT
    fi
}


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

msg=
channel=seafile-client
color="good"
uploaded_debs=""
{
    for pkg in $outputdir/*.deb; do
        /app/scripts/bintray-upload-deb --debug $pkg
        uploaded_debs="$uploaded_debs $pkg"
    done
    msg="Debs upload successfully to bintray: $uploaded_debs"
} || {
    color="bad"
    msg="Failed to upload debs to bintray"
}

/app/scripts/slack_notify.py --botname deb-travis-builder --color "$color" "$channel" "$msg" --at lins05,jiaqiangxu
