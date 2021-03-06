#!/bin/bash

DRIVER_OPTS="-d virtualbox"
SLEEP=1
NETS="overlay_services"
NETP="overlay_production"
NUM=2 #Number of Hosts and Nodes
[ -z "$WORKING_DIR" ] && WORKING_DIR=$(pwd)
[ -z "$DNSMASQ_DIR" ] && DNSMASQ_DIR="$WORKING_DIR/../docker-dnsmasq"


echo -e "********* Set up a Services Host"
echo "********* Creating a virtualbox machine called HostZ"
docker-machine create $DRIVER_OPTS "HostZ"

echo "********* Start a Zookeeper Container running on the HostZ machine"
docker $(docker-machine config "HostZ") run -d \
    -p "8181:8181" \
	-p "2181:2181" \
	-p "2888:2888" \
	-p "3888:3888" \
    -h "zookeeper" \
    jplock/zookeeper

echo "********* Start a Dnsmasq Container running on the HostZ machine"
eval $(docker-machine env HostZ)
cd "$DNSMASQ_DIR" && \
docker build -t danigiri/docker-dnsmasq .
echo "********* "
cd "$WORKING_DIR"/dnsmasq && \
docker build -t dnsmasq-eureka .

echo "********* Creating $NUM Hosts"
for (( i = 0; i < $NUM; i++ )); do
	docker-machine create $DRIVER_OPTS \
	--engine-opt="cluster-store=zk://$(docker-machine ip "HostZ"):2181" \
	--engine-opt="cluster-advertise=eth1:2376" \
	 "Host$i"
done

echo "********* Create the overlay network"
# it's only needed to create on one of the nodes of the cluster
eval $(docker-machine env Host0)

#https://docs.docker.com/engine/userguide/networking/work-with-networks/
#https://docs.docker.com/engine/reference/commandline/network_create/
docker network create --driver overlay \
--subnet=192.168.1.0/24 \
--gateway=192.168.1.1 \
--ip-range=192.168.1.128/25 \
"$NETS"

docker network create --driver overlay \
--subnet=192.168.2.0/24 \
--gateway=192.168.2.1 \
--ip-range=192.168.2.128/25 \
"$NETP"

echo "********* Creating one container inside each node and attaching to $NETS"
for (( i = 0; i < $NUM; i++ )); do
	eval $(docker-machine env "Host$i")
	docker run -d --name="Node$i" --net="$NETS" --env="constraint:node==Host$i" gliderlabs/alpine sh -c "sleep 3000"
done

eval $(docker-machine env Host0)
for (( i = 0; i < $NUM; i++ )); do
	echo "********* Pinging from Node0 to Node$i"
	docker exec "Node0" ping -c 2 "Node$i"
done