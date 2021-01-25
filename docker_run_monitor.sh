mkdir docker_logs_monitor
# docker run -it -p 9091:9090 --init --volume="$PWD/ssl:/etc/ssl/certs" --volume="$PWD/docker_logs:/app_data/logs" -e ERL_NODE_NAME="simmanager1@renegademac.arilia.com" tip-owls-1
docker run -d --init --volume="$PWD/ssl:/etc/ssl/certs" --volume="$PWD/docker_logs_monitor:/app_data/logs" --network=owls -e ERL_NODE_NAME="monitor1@renegademac.arilia.com" tip-owls-monitor