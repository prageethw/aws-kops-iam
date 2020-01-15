#!/bin/bash
source ./k8s-kops-cluster.temp

echo ""
kops replace -f $NAME.yaml
kops update cluster $NAME --yes
kops rolling-update cluster $NAME  --yes
echo ""
echo "Taging auto scalling group " $ASG_NAME
aws autoscaling \
    create-or-update-tags \
    --tags \
    ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
    ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=kubernetes.io/cluster/$NAME,Value=true,PropagateAtLaunch=true \
    ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/$NAME,Value=true,PropagateAtLaunch=true
