#!/bin/sh

# execute bash in running gitlab-runner container.
# gitlab-runner docker container was created with volume
# "-v gitlab-runner-config:/etc/gitlab-runner".
# this contains the gitlab-runner config: config.toml
# see: https://docs.gitlab.com/runner/configuration/advanced-configuration.html

docker exec -it gitlab-runner bash
