mkdir docker_logs_node1
# docker run -it -p 9091:9090 --init --volume="$PWD/ssl:/etc/ssl/certs" --volume="$PWD/docker_logs:/app_data/logs" -e ERL_NODE_NAME="simmanager1@renegademac.arilia.com" tip-owls-1
docker run -d --init --volume="$PWD/ssl:/etc/ssl/certs" --volume="$PWD/docker_logs_node1:/app_data/logs" --network=owls -e ERL_NODE_NAME="node1@renegademac.arilia.com" tip-owls-node