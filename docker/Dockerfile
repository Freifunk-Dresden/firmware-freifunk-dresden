FROM ubuntu:18.04
MAINTAINER info@lank.me

RUN apt-get update && \
	apt-get full-upgrade -y && \
	apt-get install -y nodejs git build-essential devscripts debhelper \
		dh-systemd python dh-python libssl-dev libncurses5-dev unzip \
		gawk zlib1g-dev subversion gcc-multilib flex gettext \
		wget time rsync jq && \
	apt-get clean

RUN useradd -m builder && \
	mkdir /etc/sudoers.d/ && \
	echo 'builder ALL=NOPASSWD: ALL' > /etc/sudoers.d/builder && \
	mkdir /builds && \
	chown builder:builder /builds

RUN cd /usr/src/ && \
	mkdir openwrt && \
	chown -R builder:builder openwrt

USER builder

WORKDIR /usr/src/openwrt
