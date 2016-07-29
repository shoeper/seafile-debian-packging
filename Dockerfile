FROM debian:7

ENV DEBIAN_FRONTEND noninteractive

RUN echo deb http://ftp.debian.org/debian wheezy-backports main | tee /etc/apt/sources.list.d/wheezy-backports.list && \
    apt-get update -q

RUN apt-get install -y apt-transport-https curl git python python-dev tmux vim wget \
    autotools-dev cmake debhelper intltool libcurl4-openssl-dev libevent-dev \
    libglib2.0-dev libjansson-dev libqt5webkit5-dev libsqlite3-dev libssl-dev \
    libtool qtbase5-dev qtchooser qttools5-dev qttools5-dev-tools uuid-dev valac

RUN curl -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py && \
    python /tmp/get-pip.py && \
    rm -rf /tmp/get-pip.py && \
    pip install --no-cache-dir -U wheel && \
    pip install --no-cache-dir requests[security]==2.10.0 && \
    rm -rf ~/.cache/pip

COPY pbuilderrc /root/.pbuilderrc
RUN apt-get install -y pbuilder qemu-user-static debian-archive-keyring
