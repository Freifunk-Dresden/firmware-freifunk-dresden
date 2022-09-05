# lxd gitlab-runner on main server
=================================

Step by step guide

## 1. Create a linux container (lxd) with ubuntu

## 2. Install all required dependencies to build firmware

~~~sh
apt-get install nodejs git build-essential cmake devscripts debhelper \
                dh-systemd python python3 dh-python libssl-dev libncurses5-dev unzip \
                gawk zlib1g-dev subversion gcc-multilib flex gettext curl \
                wget time rsync jq \
                libjson-c-dev libjsoncpp-dev \
                python3-pip python3-pypathlib python-pathlib2 python-scandir \
                automake autoconf m4 \
                vim tmux

~~~

## 3. Configure SSL certificates (additional hosts)

### 3a. Install letsencrypt certificates, so gitlab-runner can clone from gitlab repository

Download and copy let's encrypt root certificates

~~~sh
wget https://letsencrypt.org/certs/isrgrootx1.pem.txt -O /etc/ssl/certs/letencrypt-isrgrootx1.pem
wget https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt -O /etc/ssl/certs/lets-encrypt-x3-cross-signed.pem
wget https://letsencrypt.org/certs/letsencryptauthorityx3.pem.txt -O /etc/ssl/certs/letsencryptauthorityx3.pe

# update certificates, so system knows about the new files
update-ca-certificates --verbose --fresh

# check if website is accessable
wget -O - https://gitlab.freifunk-dresden.de/
~~~

### 3b. Or allow *ANY* SSL cerificates and add user defined domain name (example with docker executor and local cache)

Add enviroment variable "GIT_SSL_NO_VERIFY" and "tls_verify = false" in /etc/gitlab-runner/config.toml


~~~
[[runners]]
  name = "gitlab-docker"
  url = "https://gitlab.freifunk-dresden.de/"
  token = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  executor = "docker"
  environment = ["LC_ALL=en_US.UTF-8", "GIT_SSL_NO_VERIFY=true"]
  [runners.docker]
    tls_verify = false
    image = "ubuntu:18.04"
    memory = "4096m"
    memory_swap = "2048m"
    memory_reservation = "1024m"
    privileged = false
    disable_cache = false
    volumes = ["/cache"]
    cache_dir = "/cache"
    extra_hosts = ["myhost1.intern.lan:192.168.30.1","myhost2.intern.lan:192.168.40.1"]
    environment = ["LC_ALL=en_US.UTF-8", "GIT_SSL_NO_VERIFY=true"]
    pull_policy = "if-not-present"
    shm_size = 0
  [runners.cache]
    Insecure = false
~~~

## 4. Install gitlab-runner and assing a tag to it. so it can be selected by gitlab

## 5. Add .gitlab-ci.yml in your git repository

*.gitlab-ci.yml* define stages. Start with one stage, in our case with "*build*".<br>
Each runner type (here gitlab-runner without docker) should have its own job definition.
The job is selected by gitlab by checking for matching *tags*.

~~~
stages:
- build

build:ar71xx.tiny:
  stage: build
  cache:
    key: ${CI_COMMIT_REF_SLUG}
    paths:
    - dl/*
  script:
    - ./build.sh ar71xx.tiny -j8
  artifacts:
    name: "$CI_JOB_NAME-$CI_COMMIT_REF_NAME"
    paths:
    - workdir/*/bin/targets/*
    - dl
  tags:
  - m2runner

~~~
- https://docs.gitlab.com/runner/
- https://docs.gitlab.com/ce/ci/yaml/
- https://gitlab.freifunk-dresden.de/help/ci/pipelines.md
- https://gitlab.freifunk-dresden.de/help/ci/environments
- https://docs.gitlab.com/ee/ci/yaml/#skipping-jobs
- https://docs.gitlab.com/ce/ci/caching/
- https://docs.gitlab.com/runner/configuration/advanced-configuration.html
