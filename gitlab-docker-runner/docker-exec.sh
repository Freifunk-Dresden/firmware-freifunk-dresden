#!/bin/sh

# execute bash in running gitlab-runner container CREATED BY GITLAB using docker image
# that I have created..
# gitlab-runner docker container was created by Gitlab with volume
# "-v gitlab-runner-config:/etc/gitlab-runner".
# this contains the gitlab-runner config: config.toml
# see: https://docs.gitlab.com/runner/configuration/advanced-configuration.html

# for devel, I can access a running container and change default user 'builder' (defined in
# Dockerfile to root user. this allows me to install more needed packages or fix some configs
# before creating a new container image.
#
docker exec -it -u root test-container bash
