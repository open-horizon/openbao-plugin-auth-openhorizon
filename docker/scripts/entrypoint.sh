#!/usr/local/bin/dumb-init /bin/sh
set -e

# Note above that we run dumb-init as PID 1 in order to reap zombie processes
# as well as forward signals to all processes in its session. Normally, sh
# wouldn't do either of these functions so we'd leak zombies as well as do
# unclean termination of all our sub-processes.

# Prevent core dumps
ulimit -c 0

# Allow setting BAO_REDIRECT_ADDR and BAO_CLUSTER_ADDR using an interface
# name instead of an IP address. The interface name is specified using
# BAO_REDIRECT_INTERFACE and BAO_CLUSTER_INTERFACE environment variables. If
# BAO_*_ADDR is also set, the resulting URI will combine the protocol and port
# number with the IP of the named interface.
get_addr () {
    local if_name=$1
    local uri_template=$2
    ip addr show dev $if_name | awk -v uri=$uri_template '/\s*inet\s/ { \
      ip=gensub(/(.+)\/.+/, "\\1", "g", $2); \
      print gensub(/^(.+:\/\/).+(:.+)$/, "\\1" ip "\\2", "g", uri); \
      exit}'
}

if [ -z "$VAULT_DEV_LISTEN_ADDRESS" ]; then
    auto-unseal.sh &
fi

if [ -n "$BAO_REDIRECT_INTERFACE" ]; then
    export BAO_REDIRECT_ADDR=$(get_addr $BAO_REDIRECT_INTERFACE ${BAO_REDIRECT_ADDR:-"http://0.0.0.0:8200"})
    echo "Using $BAO_REDIRECT_INTERFACE for BAO_REDIRECT_ADDR: $BAO_REDIRECT_ADDR"
fi
if [ -n "$BAO_CLUSTER_INTERFACE" ]; then
    export BAO_CLUSTER_ADDR=$(get_addr $BAO_CLUSTER_INTERFACE ${BAO_CLUSTER_ADDR:-"https://0.0.0.0:8201"})
    echo "Using $BAO_CLUSTER_INTERFACE for BAO_CLUSTER_ADDR: $BAO_CLUSTER_ADDR"
fi

# BAO_CONFIG_DIR isn't exposed as a volume but you can compose additional
# config files in there if you use this image as a base, or use
# VAULT_LOCAL_CONFIG below.
VAULT_CONFIG_DIR=/vault/config

# You can also set the VAULT_LOCAL_CONFIG environment variable to pass some
# Bao configuration JSON without having to bind any volumes.
if [ -n "$VAULT_CONFIG_DIR" ]; then
    echo "$VAULT_CONFIG_DIR" > "$VAULT_CONFIG_DIR/local.json"
fi

# If the user is trying to run Bao directly with some arguments, then
# pass them to Bao.
if [ "${1:0:1}" = '-' ]; then
    set -- bao "$@"
fi

# Look for Bao subcommands.
if [ "$1" = 'server' ]; then
    shift
    set -- bao server \
        -config="$VAULT_CONFIG_DIR" \
        -dev-root-token-id="$BAO_DEV_ROOT_TOKEN_ID" \
        -dev-listen-address="${VAULT_DEV_LISTEN_ADDRESS:-"0.0.0.0:8200"}" \
        "$@"
elif [ "$1" = 'version' ]; then
    # This needs a special case because there's no help output.
    set -- bao "$@"
elif bao --help "$1" 2>&1 | grep -q "bao $1"; then
    # We can't use the return code to check for the existence of a subcommand, so
    # we have to use grep to look for a pattern in the help output.
    set -- bao "$@"
fi

# # If we are running Bao, make sure it executes as the proper user.
# if [ "$1" = 'bao' ]; then
#     if [ -z "$SKIP_CHOWN" ]; then
#         # If the config dir is bind mounted then chown it
#         if [ "$(stat -c %u /bao/config)" != "$(id -u bao)" ]; then
#             chown -R bao:bao /bao/config || echo "Could not chown /bao/config (may not have appropriate permissions)"
#         fi

#         # If the logs dir is bind mounted then chown it
#         if [ "$(stat -c %u /bao/logs)" != "$(id -u bao)" ]; then
#             chown -R bao:bao /bao/logs
#         fi

#         # If the file dir is bind mounted then chown it
#         if [ "$(stat -c %u /bao/file)" != "$(id -u bao)" ]; then
#             chown -R bao:bao /bao/file
#         fi

#         # If the exchange cert dir is bind mounted then chown it
#         if [ "$(stat -c %u /openhorizon/certs)" != "$(id -u bao)" ]; then
#             chown -R bao:bao /openhorizon/certs
#         fi
#     fi

#     if [ -z "$SKIP_SETCAP" ]; then
#         # Allow mlock to avoid swapping Bao memory to disk
#         setcap cap_ipc_lock=+ep $(readlink -f $(which bao))

#         # In the case bao has been started in a container without IPC_LOCK privileges
#         if ! bao -version 1>/dev/null 2>/dev/null; then
#             >&2 echo "Couldn't start bao with IPC_LOCK. Disabling IPC_LOCK, please use --privileged or --cap-add IPC_LOCK"
#             setcap cap_ipc_lock=-ep $(readlink -f $(which bao))
#         fi
#     fi

#     if [ "$(id -u)" = '0' ]; then
#       set -- su-exec bao "$@"
#     fi
# fi

exec "$@"