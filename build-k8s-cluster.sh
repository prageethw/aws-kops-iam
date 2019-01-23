#!/bin/bash

if [[ -z "${MY_ORG_DNS_NAME}" && -z "${MAX_NODE_COUNT}" && -z "${BASIC_AUTH_PWD}" ]]; then

    echo "You need to specify MY_ORG_DNS_NAME , MAX_NODE_COUNT and BASIC_AUTH_PWD at minimum"
    exit
fi
cd cluster
./kops-aws-prerequisite.sh
./cluster-setup.sh
