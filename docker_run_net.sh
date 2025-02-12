#!/bin/sh

HUBNAME=tip-tip-wlan-cloud-loadsim.jfrog.io
IMAGE_NAME=tip-owls-1
DOCKER_NAME=$HUBNAME/$IMAGE_NAME

NET_NAME=owls_net
# You must set this to the resolvable name of your TIP controller
TIP_CONTROLLER_HOST=debfarm1-node-a.arilia.com
TIP_CONTROLLER_IP=10.3.11.1
# This is the name of the host providing API access. In some cases, it may be the same as the TIP controller host name
TIP_API_HOST=debfarm1-node-a.arilia.com
TIP_API_IP=10.3.11.1

SIM_SCRIPT=/scripts/simulation.yaml

# clean networks and create the testing network
docker network prune --force
docker network create \
  --driver=bridge \
  --subnet=172.21.0.0/16 \
  --ip-range=172.21.10.0/24 \
  --gateway=172.21.0.1 \
  $NET_NAME

#stop previously running images
docker container stop manager node1
docker container rm manager node1 --force

#create directories for logs
rm -rf docker_logs_manager
rm -rf docker_logs_node1

mkdir docker_logs_manager
mkdir docker_logs_node1

HOSTNAMES="--add-host mgr.owls.net:172.21.10.2 --add-host node1.owls.net:172.21.10.3 --add-host $TIP_CONTROLLER_HOST:$TIP_CONTROLLER_IP --add-host $TIP_API_HOST:$TIP_API_IP"

#
# A simulation file called sim1.yaml is used to describe how a simulation should run. Here is the content...
#
# simulation:
#   name: sim1
#   ca:
#     name: tip1
#     cert: /etc/ssl/tipcert.pem   (this file should be in the $PWD/ssl dir)
#     key: /etc/ssl/tipkey.pem     (this file should be in the $PWD/ssl dir)
#     password: mypassword
#   server: (should be the same name as TIP_CONTROLLER_NAME
#   port: 6643
#   devices: 10
#
# To run a script, please replace the host line with this one in your manager section
#
# -e ERL_NODE_NAME="mgr@mgr.owls.net" -e ERL_OPTIONS="-noshell -noinput -tipauth 1 -tipapi $TIP_API_HOST -sim $SIM_SCRIPT " -e ERL_NODE_TYPE="manager" \
#
# If you are running the microk8s version of TIP, you must tell OWLS about the port to use for the API endpoint. The default is port 9051
# add the following "-tipport 9051" to the other options in your docker run manager section
#
# -e ERL_NODE_NAME="mgr@mgr.owls.net" -e ERL_OPTIONS="-noshell -noinput -tipauth 1 -tipapi $TIP_API_HOST -tipport 9051 -sim $SIM_SCRIPT " -e ERL_NODE_TYPE="manager" \
#

#start manager node
docker run  -d -p 9091:9090 --init \
            --network=owls_net \
            --volume="$PWD/ssl:/etc/ssl/certs" \
            --volume="$PWD/docker_logs_manager:/app_data/logs" \
            --volume="$PWD/scripts:/scripts" \
            -e ERL_NODE_NAME="mgr@mgr.owls.net" -e ERL_OPTIONS="-noshell -noinput -tipauth 1 -tipapi $TIP_API_HOST -sim $SIM_SCRIPT" -e ERL_NODE_TYPE="manager" \
            --ip="172.21.10.2" $HOSTNAMES \
            --name="manager" $DOCKER_NAME

#start simulation node
docker run  -d --init \
            --network=owls_net \
            --volume="$PWD/ssl:/etc/ssl/certs" \
            --volume="$PWD/docker_logs_node1:/app_data/logs" \
            -e ERL_NODE_NAME="node1@mgr.owls.net" -e ERL_OPTIONS="-noshell -noinput -tipauth 1 -tipapi $TIP_API_HOST" -e ERL_NODE_TYPE="node" \
            --ip="172.21.10.3" $HOSTNAMES \
            --name="node1" $DOCKER_NAME

