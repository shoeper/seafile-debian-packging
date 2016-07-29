FROM debian:7

ENV DEBIAN_FRONTEND noninteractive

RUN echo deb http://ftp.debian.org/debian wheezy-backports main | tee /etc/apt/sources.list.d/wheezy-backports.list && \
    apt-get update -q

RUN apt-get install -y autotools-dev cmake debhelper intltool libcurl4-openssl-dev libevent-dev libglib2.0-dev libjansson-dev libqt5webkit5-dev libsqlite3-dev libssl-dev libtool qtbase5-dev qtchooser qttools5-dev qttools5-dev-tools uuid-dev valac git tmux vim
