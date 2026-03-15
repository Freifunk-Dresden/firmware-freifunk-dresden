
# creates a docker container from docker image for testing
# uses a volume to keep the build dir

echo "using volume: openwrt-docker-build for builds (keep dl and workdir in volume)"
docker run --user "$(id -u):$(id -g)" --name test-container --rm -it -v openwrt-docker-build:/builds freifunkdresden/openwrt-docker-build /bin/bash


