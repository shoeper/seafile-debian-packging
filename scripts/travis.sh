#!/bin/bash

set -x -e

docker pull lins05/seafile-debian-builder

mapfile -t travis_env < <(env |grep TRAVIS)
docker_envs=""
for k in ${travis_env[*]}; do
    docker_envs="$docker_envs -e $k"
done

docker run --rm -it $docker_envs \
       -e "BINTRAY_AUTH=$BINTRAY_AUTH" \
       -v "$(pwd):/app" \
       --privileged \
       --name builder \
       lins05/seafile-debian-builder \
       /app/build.sh
