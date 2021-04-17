FROM ubuntu:18.04
MAINTAINER stephan@freifunk-dresden.de


RUN apt-get update && \
        apt-get full-upgrade -y && \
        apt-get install -y nodejs git build-essential devscripts debhelper \
                dh-systemd python python3 dh-python libssl-dev libncurses5-dev unzip \
                gawk zlib1g-dev subversion gcc-multilib flex gettext curl \
                wget time rsync jq \
                python-pip python-pathlib python-pathlib2 python-scandir && \
        apt-get clean

# only used when starting container by our self (not by gitlab)
# gitlab runner makes ONLY a bind mount to workdir and works a root user
# /builds will get "root" as owner (when looking in running container)
# - create user which is used to building firmware
RUN useradd -m builder

WORKDIR /builds
RUN mkdir -p /builds && chown builder:builder /builds

# create cache directories; /builds is evt used as container cache and could have
# conflicts with mycache/dl, Therefore use separate directory
RUN mkdir -p /cache && chown builder:builder /cache
RUN mkdir -p /mycache && chown builder:builder /mycache

USER builder

