https://docs.gitlab.com/runner/install/docker.html

# Install
1. There are two possibilities to install gitlab-runner.
- Install native gitlab-runner tools, which runs on host and
uses gitlab-runner/helber to build firmware with docker image.
- gitlab config: /etc/gitlab-runner/config.yaml
This allows to create openwrt-docker-build with bind-mounted
- gitlab-runner-helper mounts /mycache directly

(max runner uses this way)

  2. install gitlab-runner as docker image, that has gitlab-runner tools
in container. 
* gitlab docker (which runs gitlab-runner-helper) uses host dockerd (socket) to create more container
* configuration lays within this container (run `docker exec -it gitlab-runner bash` to access it)
* /mycache is mounted to /root/mycache (/ is not working). This is also on host available, because docker within gitlab-runner
container access the same docker socket from host.

 (stephan runner uses this way)

# Create and run container (variante 2)
~~~sh
docker run -d --name gitlab-runner --restart always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v gitlab-runner-config:/etc/gitlab-runner \
    gitlab/gitlab-runner:latest
~~~    
    
## Register docker runner with gitlab
 https://docs.gitlab.com/runner/register/#docker

 When ask for default docker image, use **registry.gitlab.freifunk-dresden.de/openwrt-docker-build:latest**
 Registration process will update /etc/gitlab-runner/config.toml (which is either
 on host (variante 1) or within the docker-runner container (variante 2)

~~~sh
docker run --rm -it -v gitlab-runner-config:/etc/gitlab-runner gitlab/gitlab-runner:latest register
~~~

## Configuration
~~~sh
docker exec -it gitlab-runner bash
~~~

add to [runners.docker] to allow loading images when those are not present on any server 
(only generated locally) but .gitlab-ci.yml has a reference to a remote docker registry
`pull_policy = ["if-not-present"]` # or `pull_policy = "if-not-present"` if service does not start (old ubuntu)

Then you need to restart either the container (in gitlab-runner runs as container) or on natively installed runner
restart with `gitlab-runner restart`.  
You may check if container or gitlab-runner service is running `service gitlab-runner status`.


## Howto use /mycache:

1. add /mycache bind mount. this is working because runner creates the openwrt-container within
   host, not within docker (not nested)
   `volumes = ["/cache", "/root/mycache:/mycache"]`
2. host: `mkdir /mycache && chmod 777 /mycache`
    This is needed because gitlab-runner bind-mounts this directory. firmware is build as user "builder"
    which is required not to be "root". It has to be able to create /root/mycache/dl and /mycache/workdir.
3. Optional if testing manually.
    - `docker run --rm -it -v "/mycache:/mycache" freifunkdresden/openwrt-docker-build bash`
    - checkout project `git clone https://gitlab.freifunk-dresden.de/firmware-developer/firmware.git`
    - `cd firmware`
    - `mkdir -p /mycache/dl /mycache/workdir`
    - `ln -s /mycache/dl && ln -s /mycache/dl`

 



