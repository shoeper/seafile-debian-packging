#!/bin/bash

set -o pipefail
set -e -x

: ${BINTRAY_UNSTABLE_REPO:?"The env BINTRAY_UNSTABLE_REPO not set"}
: ${BINTRAY_STABLE_REPO:?"The env BINTRAY_STABLE_REPO not set"}

SCRIPT=$(readlink -f "$0")
TOPDIR=$(dirname "${SCRIPT}")/..
SCRIPTSDIR=$TOPDIR/scripts/
BRANCH=lpad

OUTPUTDIR=/app/debs
mkdir -p $OUTPUTDIR
rm -f $OUTPUTDIR/*/*.deb

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
        git clone https://github.com/haiwen/${project}.git $proj_cache_dir
        cd $proj_cache_dir
        git branch -f $BRANCH origin/$BRANCH >/dev/null
    fi
    echo "file://${proj_cache_dir}"
}

get_dist_output_dir() {
    local dist=$1 arch=$2
    echo $OUTPUTDIR/$dist/$arch
}

build_deb() {
    local os=${1:?"Please specify the os"}
    local dist=${2:?"Please specify the dist"}
    local arch=${3:?"Please specify the arch"}

    local buildresult=/var/cache/pbuilder/${os}-${dist}-${arch}/result
    local dist_outputdir
    dist_outputdir=$(get_dist_output_dir ${dist} ${arch})
    mkdir -p $dist_outputdir

    local branch_args

    for project in ${projects[*]}; do
        builddir=/tmp/build64-${project}
        rm -rf $builddir
        mkdir -p $builddir && cd $builddir

        branch_args=""
        if [[ $project != "seadrive" ]]; then
            branch_args="--branch $BRANCH"
        fi

        git clone $branch_args --depth 1 "$(get_project_git_uri $project)"
        cd $project

        # Change version like 3.0.8-2 to 3.0.8.2, otherwise it would fail to
        # build on debian jessie.
        #
        # See https://github.com/jamesdbloom/grunt-debian-package/issues/23
        sed -i -e '1,1s/(\(.*\)-\(.*\))/(\1.\2)/g' debian/changelog
        echo '3.0 (native)' > debian/source/format

        if [[ $dist == "stretch" ]]; then
            sed -i -e 's/libssl-dev/libssl1.0-dev/g' debian/control
        fi

        OS=$os DIST=$dist ARCH=$arch pdebuild --debbuildopts "-j3 -nc -uc -us"

        cd $buildresult
        cp ./*.deb $dist_outputdir
    done

    upload_if_necessary $dist
}

do_upload() {
    local repo=${1:?"Please specify the repo"}
    local dist=${2:?"Please specify the dist"}
    local at_users=lins05,jiaqiangxu
    local msg=
    local channel=seafile-release
    local color="good"
    local uploaded_debs=""
    local dist_outputdir
    local upload_interval=30

    if [[ $DRONE_BRANCH != "lpad" ]]; then
        channel=shuai-test
    fi
    dist_outputdir=$(get_dist_output_dir ${dist} ${arch})
    {
        for pkg in ${dist_outputdir}/*.deb; do
            ${SCRIPTSDIR}/bintray-upload-deb --repo $repo --dist $dist --debug $pkg
            uploaded_debs="$uploaded_debs $(basename $pkg)"
            # avoid sending request to bintray too fast
            sleep $upload_interval
        done

        msg="Debs upload for \"$dist\" successfully to bintray repo \"$repo\": $uploaded_debs"

    } || {
        color="bad"
        msg="Failed to upload debs to bintray"
    }

    ${SCRIPTSDIR}/slack_notify.py --botname seafile-client-deb-builder --color "$color" "$channel" "$msg" --at "$at_users"
}

upload_if_necessary() {
    local dist=${1:?"Please specify the dist"}

    if [[ $DRONE_PULL_REQUEST != "" ]]; then
        echo "Not uploading for pull requests."
        return 0
    fi

    if [[ $DRONE_BRANCH == "lpad-dev" ]]; then
        repo=${BINTRAY_UNSTABLE_REPO}
    elif [[ $DRONE_BRANCH == "lpad" ]]; then
        repo=${BINTRAY_STABLE_REPO}
    else
        echo "Skipping uploading. To force a upload, push to the \"lpad\" branch."
        return 0
    fi

    do_upload $repo $dist
}

configs=(
    "debian,wheezy,amd64"  # debian 6 wheezy
    # "debian,wheezy,i386"  # debian 6 wheezy

    "debian,jessie,amd64"  # debian 7 jessie
    # "debian,jessie,i386"  # debian 7 jessie

    "debian,stretch,amd64"  # debian 8 stretch
    # "debian,stretch,i386"  # debian 8 stretch
)

for config in ${configs[*]}; do
    # echo ${config//,/ }
    build_deb ${config//,/ }
done
