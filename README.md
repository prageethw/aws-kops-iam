# aws-kops with iam a&a

This repo contains files that will help you to create a K8s cluster using Kops on the fly.

## required pre-conditions

1. Install AWS CLI.
2. Install JQ.
3. Create a AWS account with admin rights.
4. Helm 3.
5. IAM authenticator.
6. kops.
7. Kustomize
8. Istioctl
9. Mac OS

## set-up terminal with AWS access details

```bash
export AWS_ACCESS_KEY_ID=[...]
export AWS_SECRET_ACCESS_KEY=[...]
export AWS_DEFAULT_REGION=[...]
```

## 1. build a kops k8s cluster

```bash
MASTER_COUNT=3  MAX_NODE_COUNT=10 MIN_NODE_COUNT=2 DESIRED_NODE_COUNT=2 NODE_TYPE=t3.medium MASTER_TYPE=t2.small MY_ORG_DNS_NAME=prageethw.co USE_HELM=true UPDATE_ISTIO_MESH="" INSTALL_ISTIO_MESH=true BASIC_AUTH_PWD=abcd1234 time sh -x build-k8s-cluster.sh
```

**Note:**
Above command will create a cluster named prageethw.co.k8s.local (**Note:** DNS name will be appended with .k8s.local) with 3 master nodes and 2 worker nodes.
BASIC_AUTH_PWD is the password you need to login to monitoring and alerting systems.To set something false pass "" as the value

## 2. delete cluster

```bash
sh delete-k8s-cluster.sh
```

To cleanup all AWS resources and temporary files.

## 3. dry run

```bash
MASTER_COUNT=3 NODE_COUNT=3 NODE_SIZE=t2.small MASTER_SIZE=t2.small DRY_RUN=true MY_ORG_DNS_NAME=prageethw.co USE_HELM=true sh -x build-k8s-cluster.sh
sh delete-k8s-cluster.sh
```

## 4. distribute keys

Users of can be given a package (**.zip**) file that will be generated in /cluster/keys. as part of design there are 4 types of such packages generated ops,dev,test and admin.

## 5. RBAC and access controls

Once users get their package, they can read README.md and point them to K8s cluster. login details for Kube dashboard,monitoring and alerting tools will be displayed as part of context set.

## 6. update cluster to new K8s version

Modify version specified in kops manifest and  sh -x update-k8s-cluster.sh
