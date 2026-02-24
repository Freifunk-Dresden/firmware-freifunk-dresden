FROM debian:13
LABEL org.opencontainers.image.authors="stephan@freifunk-dresden.de"

RUN apt-get update && apt-get full-upgrade -y

# installing tzdata requires user input normally.
# to avoid blocking tzdata must be installed differently
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata

RUN apt-get install -y  python3 python3-pip python3-distutils-extra python3-standard-pipes \
                        libssl-dev libncurses5-dev unzip gawk zlib1g-dev subversion \
                        nodejs git build-essential devscripts debhelper \
                        gcc-multilib flex gettext curl wget time rsync jq tmux vim \
                        pkg-config bison flex bc lzop swig \
                        && apt-get clean

# install python2.7 for openwrt 18 targets
RUN echo "deb http://archive.debian.org/debian/ stretch contrib main non-free" > /etc/apt/sources.list.d/debian-openwrt18-packets.list; \
    apt update && apt install -y python2.7

# gitlab-runner uses /builds and /caches directories per default.
#
# chown to a new created user here does not work at all.
# gitlab starts a new container with a user (id 1000) .
# The user here should probably have the same id 1000 (builder). At least it
# must not be user "root" and also the directory (working, cloned openwrt) should have
# no "root" in this directory, which will happen, when container runs as root here.
# So "USER" is needed.
#

# chmod, so all user passed as argument when starting the container can access the directory
RUN useradd --create-home builder && chmod 777 /home/builder
WORKDIR /home/builder
USER builder

