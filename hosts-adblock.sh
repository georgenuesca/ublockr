#!/usr/bin/bash

# dnsmasq configuration file
# $1 or /etc/dnsmasq.conf
export DNSMASQ_CONFIG="${1:-/etc/dnsmasq.conf}"

# directory of this script
export DIR="$(dirname "$0")"
# directory to write the processed hosts files for dnsmasq
export HOSTS_DIR="${DIR}/hosts.d"
# IPv4 address to resolve ad-blocked hostnames to
# Do not use 127.0.0.1 if your device is running a local webserver
export IP4_ADDR="192.168.0.12"
# IPv6 address to resolve ad-blocked hostnames to
# Do not use ::1 if your device is running a local webserver
export IP6_ADDR="ffff::ffff"

# URLs to download ad-block hosts files
export URLS=""
export URLS="${URLS} local.txt"
export URLS="${URLS} https://raw.githubusercontent.com/ookangzheng/dbl-oisd-nl/master/hosts.txt"
#export URLS="${URLS} http://winhelp2002.mvps.org/hosts.txt"
#export URLS="${URLS} http://hosts-file.net/ad_servers.txt"
#export URLS="${URLS} https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext"
#export URLS="${URLS} https://www.malwaredomainlist.com/hostslist/hosts.txt"

# _test_for_required_commands
#
# Test if the required commands are available.
_test_for_required_commands() {
    export REQUIRED_CMDS="awk curl sed tr"
    export REQUIRED_CMDS_FOUND=yes

    for REQUIRED_CMD in $REQUIRED_CMDS ; do
        if ! type "${REQUIRED_CMD}" >/dev/null 2>&1 ; then
            REQUIRED_CMDS_FOUND=no
            _log "$0 needs ${REQUIRED_CMD} available in \$PATH"
        fi
    done

    if [ "${REQUIRED_CMDS_FOUND}" == "yes" ] ; then
        return 0
    else
        return 1
    fi
}

# _append_config CONTENT FILENAME
#
# Add configuration line CONTENT to FILENAME.
_append_config() {
    local CONTENT="$1"
    local FILENAME="$2"

    if ! grep -q "${CONTENT}" "${FILENAME}" ; then
        _log "Adding ${CONTENT} to ${FILENAME}"
        echo "${CONTENT}" >>"${FILENAME}"
    fi
}

# _download URL FILENAME
#
# Download the given URL and save it in the current directory as FILENAME.
_download() {
    local URL="$1"
    local FILENAME="$2"
    local CURL="curl -f -s -m 30 --connect-timeout 10 --compressed"

    if ${CURL} -s --head -o /dev/null "${URL}" ; then
        _log "Downloading/updating ${URL}"
        ${CURL} -z "${FILENAME}" -o "${FILENAME}" "${URL}"
    fi
}

# _log MESSAGE
#
# Write MESSAGE to stdout and syslog (if logger command is available).
_log() {
    echo "$1"

    if type logger >/dev/null 2>&1 ; then
        logger -t "$0" "$1"
    fi
}

# _process FILENAME
_process() {
    local FILENAME="$1"

    if [ -s "${FILENAME}" ] && ( [ "${FILENAME}" -nt "${HOSTS_DIR}/${FILENAME}" ] || ! [ -r "${HOSTS_DIR}/${FILENAME}" ]); then
        _log "Processing ${FILENAME}"
        mkdir -p "${HOSTS_DIR}"
        cat "${FILENAME}" |
        grep -v -i -e "^#" -e "localhost" |
        awk -v RS='[\n\r]+' -vIP4_ADDR="${IP4_ADDR}" -vIP6_ADDR="${IP6_ADDR}" '
            /^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|::[0-9a-fA-F]+)\s+/ {
                printf("%-16s %s\n", IP4_ADDR, $2)
#                printf("%-16s %s\n", IP6_ADDR, $2)
            }' >"${HOSTS_DIR}/${FILENAME}"
    else
        _log "Processing ${FILENAME} not required, not existing or not updated"
    fi
}

# _url_filename URL
_url_filename() {
    local URL="$1"

    echo "${URL}" |
    sed -e 's|?.*||g' -e 's|[.:/\#*+"(){}]\+|_|g' |
    tr '[A-Z]' '[a-z]'
}

_test_for_required_commands || exit $?

cd "${DIR}"

if [ -w "${DNSMASQ_CONFIG}" ] ; then
    _append_config "addn-hosts=${HOSTS_DIR}" "${DNSMASQ_CONFIG}"
fi

for URL in ${URLS} ; do
    _download "${URL}" "$(_url_filename "${URL}")" &
done

wait

for URL in ${URLS} ; do
    _process "$(_url_filename "${URL}")"
done
