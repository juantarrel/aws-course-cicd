#!/bin/bash

so-lib-get-ip() {

    local hostname=$1
    # get IP address without networking ( like laptop offline)
    if [[ $OSTYPE == darwin* ]] ; then
        CURRENT_IP=$(arp "${hostname}" | awk '{ print $2 }' | sed 's/[^0-9.]//g')
    else
        CURRENT_IP=$(getent -i ahostsv4 "${hostname}" | tail -n 1 | awk '{ print $1 }')
    fi

    if [[ -z "${CURRENT_IP}" ]] ; then
         (>&2 echo "ERROR: IP address not found for '${hostname}'")
         (>&2 echo "ERROR: Add ip address to your /etc/hosts '${hostname}'")
        exit 1;
    fi

    echo ${CURRENT_IP}
}

warn() {
    errorHeader "$@" >&2;
}

die() {
    warn "$@"; exit 1;
}


errorHeader() {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!! $1 "
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
}

header() {
    printf "${BCyan}================================================================================${Color_Off}\n"
    printf "${BYellow}$1${Color_Off}: ${BWhite}$2 ${Color_Off}\n"
    printf "${BCyan}================================================================================${Color_Off}\n"
}
