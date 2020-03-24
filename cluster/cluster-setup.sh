#!/bin/bash

#### set kops env ####
source ./set-kops.env
#unset existing kube contexts
kubectl config unset current-context
kubectl config unset users
kubectl config unset contexts
kubectl config unset clusters
echo "current kube-config is :"
kubectl config view

if [[ -z "${MY_ORG_DNS_NAME}" && -z "${MAX_NODE_COUNT}" && -z "${BASIC_AUTH_PWD}" ]]; then

    echo "You need to specify MY_ORG_DNS_NAME , MAX_NODE_COUNT and BASIC_AUTH_PWD at minimum"
    exit
else
    export BUCKET_NAME="$MY_ORG_DNS_NAME.k8s.local"-$(date +%s)
    export NAME="$MY_ORG_DNS_NAME.k8s.local"
    export DOMAIN_NAME=$MY_ORG_DNS_NAME
    export ACCNT_ID=$(aws sts get-caller-identity --output text --query Account)
    # create kms cmk
    export KMS_CMK_ARN=$(aws kms create-key --description "kms master key to encrypt/decrypt helm secrets" | jq -r '.KeyMetadata.Arn')
    #alias for CMK
    CMK_ALIAS="alias/helm-enc-dec-kms-cmk"-$(date +%s)
    aws kms create-alias --alias-name $CMK_ALIAS --target-key-id $KMS_CMK_ARN
    aws kms enable-key-rotation --key-id $KMS_CMK_ARN
    KMS_CMK_ARN_ALIAS=$KMS_CMK_ARN
    KMS_CMK_ARN_ALIAS="${KMS_CMK_ARN_ALIAS%%:key*}"
    export KMS_CMK_ARN_ALIAS="$KMS_CMK_ARN_ALIAS:$CMK_ALIAS"

    #-------
    echo "The selected k8s cluster dns name is :" $NAME
    export AWS_SSL_CERT_ARN=$(\
         aws acm request-certificate \
           --domain-name "$MY_ORG_DNS_NAME" \
           --validation-method DNS \
           --idempotency-token 91adc45q667788 \
           --options CertificateTransparencyLoggingPreference=ENABLED \
           --subject-alternative-names "*.$MY_ORG_DNS_NAME"  "*.cluster.$MY_ORG_DNS_NAME"  "cluster.$MY_ORG_DNS_NAME" \
              "*.dev.cluster.$MY_ORG_DNS_NAME"  "dev.cluster.$MY_ORG_DNS_NAME"  \
              "*.test.cluster.$MY_ORG_DNS_NAME"  "test.cluster.$MY_ORG_DNS_NAME" | jq -r \
              '.CertificateArn')
    echo "ssl cert arn is :" $AWS_SSL_CERT_ARN
    export NODE_COUNT=$MAX_NODE_COUNT
    echo ""
    echo "Maximum nodes allowed is :" $NODE_COUNT

fi


if [[ -z "${BUCKET_NAME}" ]]; then
    echo "Please define s3 bucket name for kops state persistance"
    exit
fi

#####################


#### create a s3 bucket if there is no bucket ####

BUCKET_NAME_FROM_AWS=$(aws s3api list-buckets | jq ".Buckets[] | select(.Name == \"$BUCKET_NAME\") | .Name")

# even for dry run kops need a s3 bucket to output

if [[ -z "${BUCKET_NAME_FROM_AWS}"  ]]; then

    echo "Creating an S3 bucket $BUCKET_NAME and encripting it ..."

    #create s3
    aws s3api create-bucket --bucket $BUCKET_NAME --create-bucket-configuration LocationConstraint=$AWS_DEFAULT_REGION

    # encrypt
    aws s3api put-bucket-encryption --bucket $BUCKET_NAME --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

    export KOPS_STATE_STORE=s3://$BUCKET_NAME

    echo "Kops k8s cluster will be persist in :" $KOPS_STATE_STORE
    echo ""
else
    echo "There is an already created s3 bucket  exiting ..." $BUCKET_NAME
    export KOPS_STATE_STORE=s3://$BUCKET_NAME
    echo ""
    #exit
fi

###################################################

#### create kops cluster ####

kops create cluster \
  --name $NAME \
  --master-count ${MASTER_COUNT:-3} \
  --node-count ${NODE_COUNT:-3} \
  --master-size ${MASTER_TYPE:-t3.small} \
  --node-size ${NODE_TYPE:-t3.small} \
  --zones $ZONES \
  --encrypt-etcd-storage \
  --master-zones $ZONES \
  --kubernetes-version v1.15.10 \
  --ssh-public-key ${SSH_PUBLIC_KEY:-keys/kops/kops.pub} \
  --networking kubenet \
  --authorization RBAC \
  --admin-access ${IP_WHITELIST:-0.0.0.0/0} \
  --dry-run=true \
  --output yaml > $NAME.yaml \
  --yes
  #--admin-access 72.67.80.78/10 \
  #--dry-run=${DRY_RUN:-true}
if [[ -n "${DRY_RUN}"  ]]; then
    echo ""
    echo "results from dry run logged in to $PWD/$NAME.yaml"
    echo ""
    echo " To clean dry run mess run sh delete-k8s-cluster.sh"
    echo ""
else
    
    # cat manifest-cluster.yaml | sed -e  "s@KOPS_STATE_STORE@$KOPS_STATE_STORE@g" |     tee $NAME.yaml
    cat $NAME.yaml  | sed -e  "s@minSize: $NODE_COUNT@minSize: ${MIN_NODE_COUNT:-2}@g" | tee $NAME.yaml
    #enable webhook
    sed -i '' '/anonymousAuth: false/r resources/enable-webhook.yaml' $NAME.yaml
    kops create -f $NAME.yaml
    kops create secret --name $NAME sshpublickey admin -i keys/kops/kops.pub
    kops update cluster $NAME  --yes
    CLUSTER_INIT_SLEEP=300
    echo "sleeping for initial " $CLUSTER_INIT_SLEEP "secs untill cluster available ..."
    echo "count down is ..."
    ##timer####
    while [ $CLUSTER_INIT_SLEEP -gt 0 ]; do
      echo -ne "$CLUSTER_INIT_SLEEP\033[0K\r" 
      sleep 1
      : $((CLUSTER_INIT_SLEEP--))
    done
    ############
    # sleep ${CLUSTER_INIT_SLEEP}
    SUB_SLEEP=30
    until kops validate cluster $NAME
    do
        echo "Cluster is not yet ready. Sleeping for further $SUB_SLEEP secs ..."
        echo ""
	sleep $SUB_SLEEP
    done
    #prepare auto-scaling labels to temp file.
    cat resources/auto-sacaling-tags.yaml | sed -e 's/NAME/'$NAME'/g' | tee auto-sacaling-tags.temp.yaml
    #patch manifest with autoscaling labels
    sed -i '' '/role: Node/r auto-sacaling-tags.temp.yaml' $NAME.yaml
    kops replace -f $NAME.yaml
    kops update cluster $NAME --yes
    #create name spaces
    kubectl apply -f resources/cluster-namespaces.yaml 
    #need api server name to build kube-config
    export API_SERVER_DNS="https://"$(aws elb \
    describe-load-balancers | jq -r \
    ".LoadBalancerDescriptions[] \
    | select(.DNSName \
    | contains (\"api-\")).DNSName")
###########enable rbac and user creation here as they need to compile configmap for iam authenticator #####    
    sh set-up-k8s-users.sh
#########################################
    # kubectl apply -f  iam-config-map.yaml
    kubectl  apply -f config/iam-config-map.temp.yaml
    sed -i '' '/rbac: {}/r resources/enable-iam-auth-kops.yaml' $NAME.yaml
    kops replace -f $NAME.yaml
    kops update cluster $NAME --yes
    kops rolling-update cluster ${NAME} --instance-group-roles=Master  --cloudonly --force --yes
    #kops validate cluster
    SUB_SLEEP=30
    until kops validate cluster $NAME
    do
        echo "Cluster is not yet ready. Sleeping for further $SUB_SLEEP secs ..."
        echo ""
	sleep $SUB_SLEEP
    done
##############################################################
#### fix webhook rbac
    kubectl apply -f resources/enable-webhook-rbac.yaml
####
#### intall ingress ####

    #kubectl create -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/ingress-nginx/v1.6.0.yaml
    #kubectl create -f https://raw.githubusercontent.com/prageethw/kops/master/addons/ingress-nginx/v1.6.0.yaml
    # wget -O- -q https://raw.githubusercontent.com/prageethw/kops/master/addons/ingress-nginx/v1.6.0-aws-http-ssl-redirect.yaml>k8s.nginx.yaml
    wget -O- -q https://raw.githubusercontent.com/prageethw/kops/master/addons/ingress-nginx/v1.6.0-aws-http-ssl-redirect-with-hpa-pdb.yaml>k8s.nginx.yaml
    cat k8s.nginx.yaml  | sed -e     "s@ARN@$AWS_SSL_CERT_ARN@g" |     tee k8s.nginx.yaml
    kubectl apply -f k8s.nginx.yaml
    kubectl -n kube-ingress rollout status deployment ingress-nginx

###############################################################

#### install helm if required ####

    if [[ ! -z "${USE_HELM}" ]]; then
        helm repo add stable https://kubernetes-charts.storage.googleapis.com
        helm repo add banzaicloud-stable https://kubernetes-charts.banzaicloud.com
        helm repo add flagger-stable https://flagger.app
        kubectl apply -f resources/tiller-rbac.yml 
        helm init --service-account tiller
        helm init --service-account tiller-dev --tiller-namespace dev
        helm init --service-account tiller-test --tiller-namespace test 
        helm init --service-account tiller-ops --tiller-namespace ops
        #delete service and only allow CLI helm comms , security patch as suggested here https://engineering.bitnami.com/articles/helm-security.html
        kubectl -n kube-system delete service tiller-deploy
        kubectl -n dev delete service tiller-deploy
        kubectl -n test delete service tiller-deploy
        kubectl -n ops delete service tiller-deploy
        kubectl -n kube-system patch deployment tiller-deploy --patch "$(cat resources/tiller-patch.yaml)"
        kubectl -n dev patch deployment tiller-deploy --patch "$(cat resources/tiller-patch.yaml)"
        kubectl -n test patch deployment tiller-deploy --patch "$(cat resources/tiller-patch.yaml)"
        kubectl -n ops patch deployment tiller-deploy --patch "$(cat resources/tiller-patch.yaml)"
        kubectl -n kube-system rollout status deploy tiller-deploy
        kubectl -n dev rollout status deploy tiller-deploy
        kubectl -n test rollout status deploy tiller-deploy
        kubectl -n ops rollout status deploy tiller-deploy
        kubectl apply -f resources/tiller-hpa.yaml
        kubectl apply -f resources/tiller-pdb.yaml
        #fix tiller issue https://github.com/helm/helm/issues/2861
        #kubectl apply -f resources/tiller-rbac-extend.yaml
    fi

################################################################

    export PROM_ADDR=monitor.cluster.$DOMAIN_NAME
    export AM_ADDR=alertmanager.cluster.$DOMAIN_NAME
    export GRAFANA_ADDR=grafana.cluster.$DOMAIN_NAME
    export DASHBOARD_ADDR=kubernetes-dashboard.cluster.$DOMAIN_NAME
    export MESH_GRAFANA_ADDR=mesh-grafana.cluster.$DOMAIN_NAME
    export MESH_PROM_ADDR=mesh-monitor.cluster.$DOMAIN_NAME
    export MESH_KIALI_ADDR=mesh-kiali.cluster.$DOMAIN_NAME
    export MESH_JAEGER_ADDR=mesh-jaeger.cluster.$DOMAIN_NAME


    ELB_INIT_SLEEP=60
    echo "Waiting $ELB_INIT_SLEEP sec for ELB to become available..."
    echo "count down is ..."
    while [ $ELB_INIT_SLEEP -gt 0 ]; do
      echo -ne "$ELB_INIT_SLEEP\033[0K\r" 
      sleep 1
      : $((ELB_INIT_SLEEP--))
    done
    # sleep $ELB_INIT_SLEEP

#####enable kops iam role enahnced rights ####
    export MASTER_IAM_ROLE=$(aws iam list-roles \
        | jq -r ".Roles[] \
        | select(.RoleName \
        | startswith(\"masters.$MY_ORG_DNS_NAME\")) \
        .RoleName")
    export MASTER_IAM_ROLE_ARN=$(aws iam get-role --role-name $MASTER_IAM_ROLE | jq -r .Role.Arn)
    export NODE_IAM_ROLE=$(aws iam list-roles \
        | jq -r ".Roles[] \
        | select(.RoleName \
        | startswith(\"nodes.$MY_ORG_DNS_NAME\")) \
        .RoleName")
    export NODE_IAM_ROLE_ARN=$(aws iam get-role --role-name $NODE_IAM_ROLE | jq -r .Role.Arn)
    aws iam put-role-policy \
    --role-name $NODE_IAM_ROLE \
    --policy-name nodes.$NAME-AutoScaling \
    --policy-document file://resources/kops-autoscaling-policy.json
##############################################

###### display important details that required by kubectl to interact with cluster #####

    export LB_HOST=$(kubectl -n kube-ingress \
        get svc ingress-nginx \
        -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")

    echo "ELB Host: $LB_HOST"
    echo ""
    export LB_IP="$(dig +short $LB_HOST | tail -n 1)"

    export LB_NAME=$(aws elb \
        describe-load-balancers | jq -r \
        ".LoadBalancerDescriptions[] \
        | select(.DNSName \
        | contains (\"api-\") \
        | not).LoadBalancerName")
    #wait till ingress ELB available
    echo "Waiting for ELB to become available..."
    echo ""
    aws elb wait  instance-in-service \
                      --load-balancer-name $LB_NAME

    echo "ELB IP: $LB_IP"
    echo ""
    echo "ELB NAME: $LB_NAME"
    echo ""
    echo "K8S API SERVER: $API_SERVER_DNS"
    echo ""
##### SSL offloading ########

    # export HTTP_ING_PORT=$(\
    #             kubectl --namespace kube-ingress \
    #             get all -o json | jq -r \
    #             '.items[4].spec.ports[0].nodePort')

    # echo "HTTP ING PORT: $HTTP_ING_PORT"
    # echo ""
    # delete original ELB port configs
    #aws elb delete-load-balancer-listeners --load-balancer-name $LB_NAME --load-balancer-ports 80 443

    # wait till ssl cert validated
    aws acm wait certificate-validated \
               --certificate-arn $AWS_SSL_CERT_ARN
    
    # update https listner with new config
    #aws elb create-load-balancer-listeners \
    #        --load-balancer-name $LB_NAME \
    #        --listeners "Protocol=SSL,LoadBalancerPort=443,InstanceProtocol=TCP,InstancePort=$HTTP_ING_PORT,SSLCertificateId=$AWS_SSL_CERT_ARN"

#################################

#########modify asg group####### 
 
    export ASG_NAME=$(aws autoscaling \
    describe-auto-scaling-groups \
    | jq -r ".AutoScalingGroups[] \
    | select(.AutoScalingGroupName \
    | startswith(\"nodes.$DOMAIN_NAME\")) \
    .AutoScalingGroupName")

    #tag instances so kubernetes can figure it out 
    for ID in $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --query AutoScalingGroups[].Instances[].InstanceId --output text);
    do
       aws ec2  create-tags --resources $ID --tags Key=k8s.io/cluster-autoscaler/enabled,Value=true \
                                                   Key=kubernetes.io/cluster/$NAME,Value=true \
                                                   Key=k8s.io/cluster-autoscaler/$NAME,Value=true
    done
    #tag the group incase
    aws autoscaling \
    create-or-update-tags \
    --tags \
    ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
    ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=kubernetes.io/cluster/$NAME,Value=true,PropagateAtLaunch=true \
    ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/$NAME,Value=true,PropagateAtLaunch=true
    
    #set min,max,desired numbers nodes for k8s cluster
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG_NAME --desired-capacity ${DESIRED_NODE_COUNT:-2} --min-size  ${MIN_NODE_COUNT:-2}  --max-size ${NODE_COUNT:-5}

############################################

#####install istio crds to enable external DNS to support istio gateway#######
     echo "installing istio crds "
     echo ""
     kubectl apply -f resources/istio/base/istio-crds.yaml
     echo ""

################################################################

#######install tools ###########################################

     echo "installing required tools"
     echo ""
     sh tools.sh
     echo ""

################################################################

    if [[ ! -z "${INSTALL_ISTIO_MESH}" ]]; then
        ./set-up-istio.sh
    fi

fi

echo ""
echo "------------------------------------------"
echo ""
echo "The cluster is ready. Please execute the commands that follow to create the environment variables."
echo ""
echo "export NAME=$NAME"
echo "export BUCKET_NAME=$BUCKET_NAME"
echo "export KOPS_STATE_STORE=$KOPS_STATE_STORE"
echo "export LB_IP=$LB_IP"
echo "export LB_NAME=$LB_NAME"
echo "export AWS_SSL_CERT_ARN=$AWS_SSL_CERT_ARN"
echo "export LB_HOST=$LB_HOST"
echo "export API_SERVER_DNS=$API_SERVER_DNS"
echo "export DOMAIN_NAME=$DOMAIN_NAME"
echo "export ASG_NAME=$ASG_NAME"
echo "export MASTER_IAM_ROLE_ARN=$MASTER_IAM_ROLE_ARN"
echo "export NODE_IAM_ROLE=$NODE_IAM_ROLE"
echo "export NODE_IAM_ROLE_ARN=$NODE_IAM_ROLE_ARN"
echo "export MASTER_IAM_ROLE=$MASTER_IAM_ROLE"
echo "export DESIRED_NODE_COUNT=$DESIRED_NODE_COUNT"
echo "export MIN_NODE_COUNT=$MIN_NODE_COUNT"
echo "export PROM_ADDR=$PROM_ADDR"
echo "export KMS_CMK_ARN=$KMS_CMK_ARN"
echo "export KMS_CMK_ARN_ALIAS=$KMS_CMK_ARN_ALIAS"
echo "export KMS_CMK_ALIAS=$CMK_ALIAS"
echo "export AM_ADDR=$AM_ADDR"
echo "export DASHBOARD_ADDR=$DASHBOARD_ADDR"
echo "export GRAFANA_ADDR=$GRAFANA_ADDR"
echo "export MAX_NODE_COUNT=$NODE_COUNT"
echo "export MESH_GRAFANA_ADDR=$MESH_GRAFANA_ADDR"
echo "export MESH_PROM_ADDR=$MESH_PROM_ADDR"
echo "export MESH_KIALI_ADDR=$MESH_KIALI_ADDR"
echo "export MESH_JAEGER_ADDR=$MESH_JAEGER_ADDR"
echo ""
echo "------------------------------------------"
echo ""

#####################################################################


#### dump important details to a temp file #####

echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
export ZONES=$ZONES
export NAME=$NAME
export BUCKET_NAME=$BUCKET_NAME
export LB_HOST=$LB_HOST
export DOMAIN_NAME=$DOMAIN_NAME
export API_SERVER_DNS=$API_SERVER_DNS
export AWS_SSL_CERT_ARN=$AWS_SSL_CERT_ARN
export ASG_NAME=$ASG_NAME
export NODE_IAM_ROLE=$NODE_IAM_ROLE
export NODE_IAM_ROLE_ARN=$NODE_IAM_ROLE_ARN
export PROM_ADDR=$PROM_ADDR
export AM_ADDR=$AM_ADDR
export MAX_NODE_COUNT=$NODE_COUNT
export MIN_NODE_COUNT=$MIN_NODE_COUNT
export MASTER_IAM_ROLE=$MASTER_IAM_ROLE
export MASTER_IAM_ROLE_ARN=$MASTER_IAM_ROLE_ARN
export KMS_CMK_ARN=$KMS_CMK_ARN
export KMS_CMK_ARN_ALIAS=$KMS_CMK_ARN_ALIAS
export KMS_CMK_ALIAS=$CMK_ALIAS
export GRAFANA_ADDR=$GRAFANA_ADDR
export DASHBOARD_ADDR=$DASHBOARD_ADDR
export DESIRED_NODE_COUNT=$DESIRED_NODE_COUNT
export KOPS_STATE_STORE=$KOPS_STATE_STORE
export MESH_GRAFANA_ADDR=$MESH_GRAFANA_ADDR
export MESH_PROM_ADDR=$MESH_PROM_ADDR
export MESH_KIALI_ADDR=$MESH_KIALI_ADDR
export MESH_JAEGER_ADDR=$MESH_JAEGER_ADDR" \
                                 >k8s-kops-cluster.temp

########################################################################

#### export clueter configs for distribution ####
if [[ -z "${DRY_RUN}"  ]]; then
  echo "the cluster KUBECONFIG logged in to $PWD/keys/kops/kops-kubecfg.yaml ..."

  echo ""
  echo "------------------------------------------"
  echo ""

  mkdir -p config

  export KUBECONFIG=$PWD/keys/kops/kops-kubecfg.yaml

  kops export kubecfg --name ${NAME}
  echo ""
fi
###################################################
