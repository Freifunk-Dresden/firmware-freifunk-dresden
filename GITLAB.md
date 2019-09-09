lxd gitlab-runner on main server
=================================

Create a linux container (lxd) with ubuntu
---------



Install all required dependencies to build firmware
------------
```
apt-get install unzip wget time rsync jq gawk gettext
apt-get install git subversion build-essential flex python
apt-get install libssl-dev libncurses5-dev zlib1g-dev zlib1g-dev gcc-multilib
```

Install letsencrypt certificates, so gitlab-runner can clone from gitlab repository
--------
Download and copy let's encrypt root certificates

```
 wget https://letsencrypt.org/certs/isrgrootx1.pem.txt -O /etc/ssl/certs/letencrypt-isrgrootx1.pem
 wget https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt -O /etc/ssl/certs/lets-encrypt-x3-cross-signed.pem
 wget https://letsencrypt.org/certs/letsencryptauthorityx3.pem.txt -O /etc/ssl/certs/letsencryptauthorityx3.pe
 
 # update certificates, so system knows about the new files
 update-ca-certificates --verbose --fresh

 # check if website is accessable
 wget -O - https://gitlab.freifunk-dresden.de/
```

Install gitlab-runner and assing a tag to it. so it can be selected by gitlab
---------


.gitlab-ci.yml
--------------
*.gitlab-ci.yml* define stages. Start with one stage, in our case with "*build*".<br>
Each runner type (here gitlab-runner without docker) should have its own job definition.
The job is selected by gitlab by checking for matching *tags*.

```
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

```
- https://docs.gitlab.com/runner/
- https://docs.gitlab.com/ce/ci/yaml/
- https://gitlab.freifunk-dresden.de/help/ci/pipelines.md
- https://gitlab.freifunk-dresden.de/help/ci/environments
- https://docs.gitlab.com/ee/ci/yaml/#skipping-jobs
- https://docs.gitlab.com/ce/ci/caching/

