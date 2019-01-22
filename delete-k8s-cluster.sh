#!/bin/bash
cd cluster
source ./k8s-kops-cluster.temp
./delete-kops.sh
./kops-aws-prerequisite-cleanup.sh
