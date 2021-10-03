https://docs.gitlab.com/runner/install/docker.html

# Install
1. There are two possibilities to install gitlab-runner.
Install native gitlab-runner tools, which runs on host and
      uses gitlab-runner/helber to build firmware with docker image.
      This allows to create openwrt-docker-build with bind-mounted
      /mycache directory. /mycache would then hold working dir and dl dir
(max runner uses this way)

  2. install gitlab-runner as docker image, that has gitlab-runner tools
      in container. this container runs always to speak with gitlab server.
      The runners config is within the container.
 (stephan runner uses this way)

# create and run container (variante 2)
----------------------------------------------
~~~sh
docker run -d --name gitlab-runner --restart always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v gitlab-runner-config:/etc/gitlab-runner \
    gitlab/gitlab-runner:latest
~~~    
    
## register docker runner with gitlab
 https://docs.gitlab.com/runner/register/#docker

 When ask for default docker image, use "registry.gitlab.freifunk-dresden.de/openwrt-docker-build:latest"
 Registration process will update /etc/gitlab-runner/config.toml (which is either
 on host (variante 1) or within the docker-runner container (variante 2)

~~~sh
docker run --rm -it -v gitlab-runner-config:/etc/gitlab-runner gitlab/gitlab-runner:latest register
~~~

## modify docker configuration and restart container.

~~~sh
docker exec -it gitlab-runner bash
~~~

## configuration
add to [runners.docker] to allow loading images when those are not present on any server 
(only generated locally) but .gitlab-ci.yml has a reference to a remote docker registry
`pull_policy = ["if-not-present"]`


## Howto use /mycache:

1. add /mycache bind mount. this is working because runner creates the openwrt-container within
   host, not within docker (not nested)
   `volumes = ["/cache", "/root/mycache:/mycache"]`
2. host: `mkdir /mycache && chmod 777 /mycache`
    This is needed because gitlab-runner bind-mounts this directory. firmware is build as user "builder"
    which is required not to be "root". It has to be able to create /root/mycache/dl and /mycache/workdir.
3. Optional if testing manually.
    - `docker run --rm -it -v "/mycache:/mycache" openwrt-docker-build bash`
    - checkout project
    - `cd firmware`
    - `mkdir -p /mycache/dl /mycache/workdir`
    - `ln -s /mycache/dl && ln -s /mycache/dl`

 



