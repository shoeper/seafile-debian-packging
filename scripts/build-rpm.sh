#!/bin/bash

set -e -x
set -o pipefail

SCRIPT=$(readlink -f "$0")
TOPDIR=$(dirname "${SCRIPT}")/..
SCRIPTSDIR=$TOPDIR/scripts/
BRANCH=rpm-release
TRIGGER_BRANCH=rpm-release

OUTPUTDIR=/app/rpms
mkdir -p $OUTPUTDIR
rm -f $OUTPUTDIR/*.rpm

# searpc install dir
SEARPC_TMP_INSTALLDIR=/app/installdir/searpc
rm -rf ${SEARPC_TMP_INSTALLDIR}/*
SEARPC_PREFIX=$SEARPC_TMP_INSTALLDIR/usr
mkdir -p $SEARPC_PREFIX/{bin,lib,include,share}

# seafile install dir
SEAFILE_TMP_INSTALLDIR=/app/installdir/seafile
rm -rf ${SEAFILE_TMP_INSTALLDIR}/*
SEAFILE_PREFIX=$SEAFILE_TMP_INSTALLDIR/usr
mkdir -p $SEAFILE_PREFIX/{bin,lib,include,share}

# seafile-client install dir
SEAFILECLIENT_TMP_INSTALLDIR=/app/installdir/seafileclient
rm -rf ${SEAFILECLIENT_TMP_INSTALLDIR}/*
SEAFILECLIENT_PREFIX=$SEAFILECLIENT_TMP_INSTALLDIR/usr
mkdir -p $SEAFILECLIENT_PREFIX/{bin,lib,include,share}

export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$SEARPC_PREFIX/lib/pkgconfig:$SEARPC_PREFIX/lib64/pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$SEAFILE_PREFIX/lib/pkgconfig:$SEAFILE_PREFIX/lib64/pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$SEAFILECLIENT_PREFIX/lib/pkgconfig:$SEAFILECLIENT_PREFIX/lib64/pkgconfig

export PATH=$PATH:$SEARPC_PREFIX/bin
export PATH=$PATH:$SEAFILE_PREFIX/bin
export PATH=$PATH:$SEAFILECLIENT_PREFIX/bin

jobs=3

projects=(
    libsearpc
    seafile
    seafile-client
)

GIT_CACHE_DIR=/tmp/gitcache
mkdir -p $GIT_CACHE_DIR

get_project_git_uri() {
    local project=$1

    local proj_cache_dir=${GIT_CACHE_DIR}/${project}
    if [[ ! -e $proj_cache_dir ]]; then
        git clone -q https://github.com/haiwen/${project}.git $proj_cache_dir
    fi
    cd $proj_cache_dir
    git fetch
    git branch -f $BRANCH origin/$BRANCH >/dev/null
    echo "file://${proj_cache_dir}"
}

build_rpm() {
    local dist=${1:?"Please specify the dist"}

    local branch_args
    local seafile_version
    local searpc_version
    for project in ${projects[*]}; do
        builddir=/tmp/build64-${project}
        rm -rf $builddir
        mkdir -p $builddir && cd $builddir

        branch_args="--branch $BRANCH"
        git clone $branch_args --depth 1 "$(get_project_git_uri $project)"
        cd $project

        if [[ $project == "libsearpc" ]]; then
            searpc_version=$(head -n 1 debian/changelog|awk -F "[()]" '{print $2}')
        fi
        if [[ $project == "seafile" ]]; then
            seafile_version=$(grep -E --only-matching 'CurrentSeafileVersion=".*"' msi/Includes.wxi|awk -F "\"" '{print $2}')
        fi

        if [[ $project == "seafile-client" ]]; then
            cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$SEAFILECLIENT_PREFIX .
            make -j$jobs
            make install

        elif [[ $project == "seafile" ]]; then
            ./autogen.sh
            ./configure --prefix=/usr
            make -j$jobs
            make install DESTDIR=$SEAFILE_TMP_INSTALLDIR
        else
            ./autogen.sh
            ./configure --prefix=/usr
            make -j$jobs
            make install DESTDIR=$SEAFILE_TMP_INSTALLDIR
        fi
    done

    pack_rpm_searpc ${searpc_version?:"Failed to parse seafile version"} $dist
    pack_rpm_seafile ${seafile_version?:"Failed to parse seafile version"} $dist
    pack_rpm_seafile_client ${seafile_version?:"Failed to parse seafile version"} $dist
    upload_if_necessary $dist
}

prepare_pack_rpm() {
    postinst=/tmp/postinst
    echo "ldconfig" > $postinst

    rm -rf $1/include
    rm -rf $1/lib/*.la
    rm -rf $1/lib/*.a
    rm -rf $1/lib/pkgconfig
    rm -rf $1/lib64/*.la
    rm -rf $1/lib64/*.a
    rm -rf $1/lib64/pkgconfig
    rm -rf $1/include

    if [[ $3 == "libsearpc" ]]; then
        dirs="usr/share"
    else
        dirs="usr/bin usr/share"
    fi
    # fedora installs libs to usr/lib64 while centos uses usr/lib/
    local optional_dirs=(
        usr/lib
        usr/lib64
    )
    for d in ${optional_dirs[*]}; do
        if find $2/${d} -type f | grep -q '.'; then
            dirs="$dirs $d"
        fi
    done
}

# searpc package
pack_rpm_searpc() {
    local version=${1:?"Please specify the version"}
    prepare_pack_rpm ${SEARPC_PREFIX} ${SEARPC_TMP_INSTALLDIR} "libsearpc"

    cd $OUTPUTDIR
    fpm -s dir -n libsearpc -v $version \
        --exclude ${SEARPC_TMP_INSTALLDIR}/usr/bin \
        --description "Seafile searpc" \
        --url "https://github.com/haiwen/libsearpc" \
        --category misc \
        --vendor "" \
        -m info@seafile.com \
        --chdir $SEARPC_TMP_INSTALLDIR \
        -t rpm \
        -d glib2 \
        -d "jansson >= 2.2.1" \
        -p libsearpc_VERSION_ARCH.rpm \
        --after-install $postinst \
        $dirs
}

# seadrive package
pack_rpm_seafile() {
    local version=${1:?"Please specify the version"}
    prepare_pack_rpm ${SEAFILE_PREFIX} ${SEAFILE_TMP_INSTALLDIR}

    cd $OUTPUTDIR
    fpm -s dir -n seafile-daemon -v $version \
        --description "Seafile Daemon" \
        --url "https://github.com/haiwen/seafile" \
        --category misc \
        --vendor "" \
        -m info@seafile.com \
        --chdir $SEAFILE_TMP_INSTALLDIR \
        -t rpm \
        -d libcurl \
        -d glib2 \
        -d "jansson >= 2.2.1" \
        -d "libevent >= 2.0" \
        -d "openssl-libs >= 1.0.0" \
        -d "sqlite >= 3.0" \
        -d python2-future \
        -d fuse-libs \
        -d libuuid \
        -d libsearpc \
        -p seafile-daemon_VERSION_ARCH.rpm \
        --after-install $postinst \
        $dirs
}

# seafile-client package
pack_rpm_seafile_client() {
    local version=${1:?"Please specify the version"}
    local dist=$2
    prepare_pack_rpm ${SEAFILECLIENT_PREFIX} ${SEAFILECLIENT_TMP_INSTALLDIR}

    local qtwebengine=qt5-qtwebengine
    if [[ $dist == centos* ]]; then
        # CentOS 7 doesn't have qt webengine yet.
        qtwebengine=qt5-qtwebkit
    fi

    cd $OUTPUTDIR
    fpm -s dir -n seafile -v $version \
        --description "Seafile Client" \
        --url "https://github.com/haiwen/seafile" \
        --category misc \
        --vendor "" \
        -m info@seafile.com \
        --chdir $SEAFILECLIENT_TMP_INSTALLDIR \
        -t rpm \
        -d glib2 \
        -d "jansson >= 2.2.1" \
        -d "libevent >= 2.0" \
        -d "openssl-libs >= 1.0.0" \
        -d "sqlite >= 3.0" \
        -d libuuid \
        -d qt5-qtbase \
        -d $qtwebengine \
        -d libsearpc \
        -d seafile-daemon \
        -p seafile_VERSION_ARCH.rpm \
        --after-install $postinst \
        $dirs
}

do_upload() {
    local repo=${1:?"Please specify the repo"}
    local dist=${2:?"Please specify the dist"}
    local at_users=lins05,jiaqiangxu
    local msg=
    local channel=seafile-release
    local color="good"
    local uploaded_rpms=""
    local dist_outputdir

    if [[ $DRONE_BRANCH != "${TRIGGER_BRANCH}" ]]; then
        channel=shuai-test
    fi
    {
        for pkg in $OUTPUTDIR/*.rpm; do
            ${SCRIPTSDIR}/bintray-upload-rpm --repo $repo --dist $dist --debug $pkg
            uploaded_rpms="$uploaded_rpms $(basename $pkg)"
        done

        msg="RPMS upload for \"$dist\" successfully to bintray repo \"$repo\": $uploaded_rpms"

    } || {
        color="bad"
        msg="Failed to upload rpms to bintray"
    }

    ${SCRIPTSDIR}/slack_notify.py --botname seafile-client-rpm-drone-builder --color "$color" "$channel" "$msg" --at "$at_users"
}

upload_if_necessary() {
    local dist=${1:?"Please specify the dist"}

    if [[ $DRONE_PULL_REQUEST != "" ]]; then
        echo "Not uploading for pull requests."
        return 0
    fi

    if [[ $DRONE_BRANCH == "${TRIGGER_BRANCH}-dev" ]]; then
        repo=haiwen-org/rpm-unstable
    elif [[ $DRONE_BRANCH == "${TRIGGER_BRANCH}" ]]; then
        repo=haiwen-org/rpm
    else
        echo "Skipping uploading. To force a upload, push to the \"${TRIGGER_BRANCH}\" branch."
        return 0
    fi

    do_upload $repo $dist
}

build_rpm $1