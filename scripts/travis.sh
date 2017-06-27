#!/bin/bash

set -e

image=lins05/seadrive-builder:latest
container=seafile-client-deb-builder

mapfile -t travis_env < <(env |grep TRAVIS)
docker_envs=""
for k in ${travis_env[*]}; do
    docker_envs="$docker_envs -e $k"
done

if docker inspect $container; then
    docker rm -f $container
fi

docker run -it $docker_envs \
       -e "BINTRAY_AUTH=$BINTRAY_AUTH" \
       -e "SLACK_NOTIFY_URL=$SLACK_NOTIFY_URL" \
       -v "$(pwd):/app" \
       --privileged \
       --name $container \
       $image \
       /app/scripts/build-debs.sh

       # bash -c '/app/scripts/build-debs.sh || sleep 30000'
