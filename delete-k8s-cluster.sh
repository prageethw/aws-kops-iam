#!/bin/bash
set -x
cd cluster
./delete-kops.sh
./kops-aws-prerequisite-cleanup.sh
