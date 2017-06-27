#!/bin/bash 
set -x
set -e

# Stop host mongo and rabbitmq service
# otherwise mongo and rabbitmq service won't run normally
# use host mongo and rabbitmq is a chioce but the coverage may be decreased.
# services will be restart in cleanup.sh, which script will always be executed.
echo $SUDO_PASSWORD |sudo -S service mongodb stop
echo $SUDO_PASSWORD |sudo -S service rabbitmq-server stop

rackhd_docker_images=`ls ${DOCKER_PATH}`
# load docker images
docker load -i $rackhd_docker_images | tee ${WORKSPACE}/docker_load_output

if [ ${USE_PREBUILT_IMAGES} == true ] ; then
    # This path is followed when using the posttest tag and running from an already build docker tarball
    file=${WORKSPACE}/docker_load_output
    while IFS=:  read -r load imagename tag 
    do
       echo $tag
       break
    done < "$file"
    posttest_list=$(echo "rackhd/files:${tag} rackhd/on-core:${tag} rackhd/on-syslog:${tag} rackhd/on-dhcp-proxy:${tag} \
                          rackhd/on-tftp:${tag} rackhd/on-wss:${tag} rackhd/on-statsd:${tag} rackhd/on-tasks:${tag} rackhd/on-taskgraph:${tag} \
                          rackhd/on-http:${tag} rackhd/ucs-service:${tag}")
    echo $posttest_list >> ${WORKSPACE}/build_record
    DOCKER_RECORD_PATH=${WORKSPACE}/build_record
fi
build_record=`ls ${DOCKER_RECORD_PATH}`

image_list=`head -n 1 $build_record`

pushd $BUILD_CONFIG_DIR
find ./ -type f -exec sed -i -e "s/172.31.128.1/$DOCKER_RACKHD_IP/g" {} \;
popd

pushd $RackHD_DIR/test
# in vagrant or ova， rackhd ip are all default  172.31.128.1
# but for docker containers it‘s hard to virtualize such a IP
# so replace it with DOCKER_RACKHD_IP which is usually the eth1 IP of vmslave
find ./ -type f -exec sed -i -e "s/172.31.128.1/$DOCKER_RACKHD_IP/g" {} \;
popd

# this step must behind sed replace
cd $RackHD_DIR/docker
# replace default config json with the one which is for test.
cp -f ${WORKSPACE}/build-config/vagrant/config/mongo/config.json ./monorail/config.json
#if clone file name is not repo name, this scirpt should be edited.
for repo_tag in $image_list; do
    repo=${repo_tag%:*}
    sed -i "s#${repo}.*#${repo_tag}#g" docker-compose-mini.yml
done

mkdir -p $WORKSPACE/build-log
n=0
until [ $n -ge 2 ]
do
    docker-compose -f docker-compose-mini.yml pull && break
    n=$[$n+1]
    sleep 5
done
docker-compose -f docker-compose-mini.yml up > $WORKSPACE/build-log/vagrant.log &

