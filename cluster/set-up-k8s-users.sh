#!/bin/bash
set -x
#create user groups
aws iam create-group --group-name kops-dev
aws iam create-group --group-name kops-test
aws iam create-group --group-name kops-ops
aws iam create-group --group-name kops-admin

#create users
export DEV_USER_ARN=$(aws iam create-user --user-name kops-dev | jq -r .User.Arn)
export TEST_USER_ARN=$(aws iam create-user --user-name kops-test | jq -r .User.Arn)
export OPS_USER_ARN=$(aws iam create-user --user-name kops-ops | jq -r .User.Arn)
export ADMIN_USER_ARN=$(aws iam create-user --user-name kops-admin | jq -r .User.Arn)

#add users to the group
aws iam add-user-to-group \
    --user-name kops-dev \
    --group-name kops-dev
    
aws iam add-user-to-group \
    --user-name kops-test \
    --group-name kops-test
    
aws iam add-user-to-group \
    --user-name kops-ops \
    --group-name kops-ops
    
aws iam add-user-to-group \
    --user-name kops-admin \
    --group-name kops-admin
    
mkdir -p config
#create policy doc
cat resources/assume-dev-kops-iam-role-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee config/assume-dev-kops-iam-role-policy.temp.json
cat resources/assume-test-kops-iam-role-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee config/assume-test-kops-iam-role-policy.temp.json
cat resources/assume-ops-kops-iam-role-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee config/assume-ops-kops-iam-role-policy.temp.json
cat resources/assume-admin-kops-iam-role-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee config/assume-admin-kops-iam-role-policy.temp.json
#create roles
export DEV_ROLE_ARN=$(aws iam create-role --role-name kops-dev --assume-role-policy-document file://config/assume-dev-kops-iam-role-policy.temp.json | jq -r .Role.Arn)
export TEST_ROLE_ARN=$(aws iam create-role --role-name kops-test --assume-role-policy-document file://config/assume-test-kops-iam-role-policy.temp.json | jq -r .Role.Arn)
export OPS_ROLE_ARN=$(aws iam create-role --role-name kops-ops --assume-role-policy-document file://config/assume-ops-kops-iam-role-policy.temp.json | jq -r .Role.Arn)
export ADMIN_ROLE_ARN=$(aws iam create-role --role-name kops-admin --assume-role-policy-document file://config/assume-admin-kops-iam-role-policy.temp.json | jq -r .Role.Arn)
#create group policy
cat resources/dev-kops-iam-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee config/dev-kops-iam-policy.temp.json
cat resources/test-kops-iam-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee config/test-kops-iam-policy.temp.json
cat resources/ops-kops-iam-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee config/ops-kops-iam-policy.temp.json
cat resources/admin-kops-iam-policy.json | sed -e "s@ACCOUNT_ID@$ACCNT_ID@g" | tee config/admin-kops-iam-policy.temp.json
#assign group policy to the groups
aws iam put-group-policy \
    --group-name kops-dev \
    --policy-name kops-dev \
    --policy-document file://config/dev-kops-iam-policy.temp.json
aws iam put-group-policy \
    --group-name kops-test \
    --policy-name kops-test \
    --policy-document file://config/test-kops-iam-policy.temp.json
aws iam put-group-policy \
    --group-name kops-ops \
    --policy-name kops-ops\
    --policy-document file://config/ops-kops-iam-policy.temp.json
aws iam put-group-policy \
    --group-name kops-admin \
    --policy-name kops-admin \
    --policy-document file://config/admin-kops-iam-policy.temp.json

##download keys
mkdir -p keys/dev
aws iam create-access-key --user-name kops-dev >keys/dev/kops-dev-creds
mkdir -p keys/test
aws iam create-access-key --user-name kops-test >keys/test/kops-test-creds
mkdir -p keys/ops
aws iam create-access-key --user-name kops-ops >keys/ops/kops-ops-creds
mkdir -p keys/admin
aws iam create-access-key --user-name kops-admin >keys/admin/kops-admin-creds

##patch aws-auth config with added iam 
#create admin user kube config
cat resources/iam-config-map.yaml  | sed -e "s@dev-arn@$DEV_ROLE_ARN@g" \
                                   | sed -e "s@test-arn@$TEST_ROLE_ARN@g" \
                                   | sed -e "s@NAME@$NAME@g" \
                                   | sed -e "s@ops-arn@$OPS_ROLE_ARN@g" \
                                   | sed -e "s@admin-arn@$ADMIN_ROLE_ARN@g" \
                                   | sed -e "s@NODE_IAM_ROLE_ARN@$NODE_IAM_ROLE_ARN@g" \
                                   | sed -e "s@ACCNT_ID@$ACCNT_ID@g" \
                                   | sed -e "s@MASTER_IAM_ROLE_ARN@$MASTER_IAM_ROLE_ARN@g" \
                                   | tee config/iam-config-map.temp.yaml

# kubectl  apply -f config/iam-config-map.temp.yaml
# kubectl patch cm aws-auth --patch "$(cat config/patch-aws-auth.temp.yaml)" -n kube-system
CA_AUTHORITY_DATA=$(kubectl config view --raw -o json |jq -r '.clusters[0].cluster."certificate-authority-data"')

#create dev user kube config
cat resources/kops-kube-config.yaml | sed -e "s@endpoint-url@$API_SERVER_DNS@g" \
                                   | sed -e "s@base64-encoded-ca-cert@$CA_AUTHORITY_DATA@g" \
                                   | sed -e "s@cluster-name@$NAME@g" \
                                   | sed -e "s@role-arn@$DEV_ROLE_ARN@g" \
                                   | sed -e "s@common-name@dev@g" \
                                   | sed -e "s@kubernetes@dev@g" \
                                   | tee keys/dev/dev-kops-kube-config.yaml
#create test user kube config
cat resources/kops-kube-config.yaml | sed -e "s@endpoint-url@$API_SERVER_DNS@g" \
                                   | sed -e "s@base64-encoded-ca-cert@$CA_AUTHORITY_DATA@g" \
                                   | sed -e "s@cluster-name@$NAME@g" \
                                   | sed -e "s@role-arn@$TEST_ROLE_ARN@g" \
                                   | sed -e "s@common-name@test@g" \
                                   | sed -e "s@kubernetes@test@g" \
                                   | tee keys/test/test-kops-kube-config.yaml
#create ops user kube config
cat resources/kops-kube-config.yaml | sed -e "s@endpoint-url@$API_SERVER_DNS@g" \
                                   | sed -e "s@base64-encoded-ca-cert@$CA_AUTHORITY_DATA@g" \
                                   | sed -e "s@cluster-name@$NAME@g" \
                                   | sed -e "s@role-arn@$OPS_ROLE_ARN@g" \
                                   | sed -e "s@common-name@ops@g" \
                                   | sed -e "s@kubernetes@ops@g" \
                                   | tee keys/ops/ops-kops-kube-config.yaml
#create admin user kube config
cat resources/kops-kube-config.yaml | sed -e "s@endpoint-url@$API_SERVER_DNS@g" \
                                   | sed -e "s@base64-encoded-ca-cert@$CA_AUTHORITY_DATA@g" \
                                   | sed -e "s@cluster-name@$NAME@g" \
                                   | sed -e "s@role-arn@$ADMIN_ROLE_ARN@g" \
                                   | sed -e "s@common-name@admin-user@g" \
                                   | sed -e "s@kubernetes@admin-user@g" \
                                   | tee keys/admin/admin-kops-kube-config.yaml
#############rbac enable##########

kubectl apply -f resources/rbac-dev.yaml
kubectl apply -f resources/rbac-test.yaml
kubectl apply -f resources/rbac-ops.yaml
kubectl apply -f resources/rbac-admin-user.yaml
kubectl apply -f resources/default-resources.yaml
kubectl apply -f resources/dev-resources.yaml
# kubectl apply -f resources/ingestor-resources.yaml
kubectl apply -f resources/prod-resources.yaml
kubectl apply -f resources/test-resources.yaml
kubectl apply -f resources/ops-resources.yaml

################################

#####rbac tests #####
#validate that all users can view resources in all namespaces

set -x
echo "should be yes "
kubectl auth can-i get pods --as test --all-namespaces
kubectl auth can-i get pods --as ops --all-namespaces
kubectl auth can-i get pods --as dev --all-namespaces
echo ""
##validate admin rights
echo "should be no "
kubectl auth can-i create pods --as  test --all-namespaces
kubectl auth can-i create pods --as  dev  --all-namespaces
kubectl auth can-i create pods --as  ops  --all-namespaces
echo ""
echo "should be yes "
kubectl auth can-i create pods --as  test -n test
kubectl auth can-i create pods --as  dev  -n dev
kubectl auth can-i create pods --as  dev  -n test
kubectl auth can-i create pods --as  ops  -n ops
kubectl auth can-i create pods --as  ops  -n test
kubectl auth can-i create pods --as  ops  -n dev
kubectl auth can-i create pods --as  ops  -n ingestor
kubectl auth can-i create pods --as  ops  -n prod
echo ""
echo "should be no "
##validate no super user access for k8s users
#should be no
kubectl --namespace dev auth can-i \
    "*" "*" --as dev

kubectl --namespace test auth can-i \
    "*" "*" --as test

kubectl  auth can-i \
        "*" "*" --as ops --all-namespaces
echo ""
echo "should be yes "
kubectl  auth can-i \
        "*" "*" --as admin-user --all-namespaces
set +x
##########################

##--------------------
echo "
export KUBECONFIG=\$PWD/dev-kops-kube-config.yaml

export AWS_ACCESS_KEY_ID=$(\
  cat keys/dev/*-creds | jq -r \
  '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/dev/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')

echo \"\"
echo \"to set KUBECONFIG and start using k8s execute below in your terminal\"
echo \"------------------------------\"
echo \"export KUBECONFIG=\$PWD/dev-kops-kube-config.yaml\"
echo \"export AWS_ACCESS_KEY_ID=$(\
  cat keys/dev/*-creds | jq -r \
  '.AccessKey.AccessKeyId')\"
echo \"export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/dev/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')\"
# echo \"\"
# echo \"To login to grafana use below token : it has an expiry so you will need to regenerate if its expired \"
# echo \"\"
# kubectl -n metrics \
#     get secret grafana \
#     -o jsonpath=\"{.data.admin-password}\" \
#     | base64 --decode; echo
echo \"-------------------------------\"
echo \"To login to kube dashboard use below token : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n dev describe secret \$(kubectl -n dev get secret | grep dev-sa  | awk '{print \$1}') | grep token:
echo \"\"
echo \"You can re-generate a token by running below command afer initial context setting \"
echo \"\"
echo \"-------------------------------------------------------\"
echo \"kubectl -n dev describe secret \$(kubectl -n dev get secret | grep dev-sa  | awk '{print \$1}') | grep token: \"
echo \"-------------------------------------------------------\""> keys/dev/set-up-dev.sh

##---------------
echo "
export KUBECONFIG=\$PWD/test-kops-kube-config.yaml

export AWS_ACCESS_KEY_ID=$(\
  cat keys/test/*-creds | jq -r \
  '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/test/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')

echo \"\"
echo \"to set KUBECONFIG and start using k8s execute below in your terminal\"
echo \"------------------------------\"
echo \"export KUBECONFIG=\$PWD/test-kops-kube-config.yaml\"
echo \"export AWS_ACCESS_KEY_ID=$(\
  cat keys/test/*-creds | jq -r \
  '.AccessKey.AccessKeyId')\"
echo \"export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/test/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')\"
echo \"-------------------------------\"
# echo \"\"
# echo \"To login to grafana use below token : it has an expiry so you will need to regenerate if its expired \"
# echo \"\"
# kubectl -n metrics \
#     get secret grafana \
#     -o jsonpath=\"{.data.admin-password}\" \
#     | base64 --decode; echo
echo \"\"
echo \"To login to kube dashboard use below token : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n test describe secret \$(kubectl -n test get secret | grep test-sa | awk '{print \$1}') | grep token:
echo \"\"
echo \"You can re-generate a token by running below command afer initial context setting \"
echo \"\"
echo \"-------------------------------------------------------\"
echo \"kubectl -n test describe secret $(kubectl -n test get secret | grep test-sa | awk '{print $1}') | grep token: \"
echo \"-------------------------------------------------------\"" > keys/test/set-up-test.sh

##----------
echo "
export KUBECONFIG=\$PWD/ops-kops-kube-config.yaml

export AWS_ACCESS_KEY_ID=$(\
  cat keys/ops/*-creds | jq -r \
  '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/ops/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')

echo \"\"
echo \"to set KUBECONFIG and start using k8s execute below in your terminal\"
echo \"------------------------------\"
echo \"export KUBECONFIG=\$PWD/ops-kops-kube-config.yaml\"
echo \"export AWS_ACCESS_KEY_ID=$(\
  cat keys/ops/*-creds | jq -r \
  '.AccessKey.AccessKeyId')\"
echo \"export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/ops/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')\"
echo \"-------------------------------\"

echo \"\"
echo \"your monitoring and alerting portal uid/password :\" sysops:$BASIC_AUTH_PWD
echo \"\"

# echo \"To login to grafana use below token with admin as userid : it has an expiry so you will need to regenerate if its expired \"
# echo \"\"
# kubectl -n metrics \
#     get secret grafana \
#     -o jsonpath=\"{.data.admin-password}\" \
#     | base64 --decode; echo

echo \"\"
echo \"To login to kube dashboard use below token : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n test describe secret \$(kubectl -n test get secret | grep test-sa | awk '{print \$1}') | grep token:
echo \"\"
echo \"You can re-generate a token by running below command afer initial context setting \"
echo \"-------------------------------\"
echo \"kubectl -n ops describe secret $(kubectl -n ops get secret | grep ops-sa | awk '{print $1}') | grep token: \"
echo \"-------------------------------\""> keys/ops/set-up-ops.sh

##----------
echo "
export KUBECONFIG=\$PWD/admin-kops-kube-config.yaml

export AWS_ACCESS_KEY_ID=$(\
  cat keys/admin/*-creds | jq -r \
  '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/admin/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')

echo \"\"
echo \"to set KUBECONFIG and start using k8s execute below in your terminal\"
echo \"------------------------------\"
echo \"export KUBECONFIG=\$PWD/admin-kops-kube-config.yaml\"
echo \"export AWS_ACCESS_KEY_ID=$(\
  cat keys/admin/*-creds | jq -r \
  '.AccessKey.AccessKeyId')\"
echo \"export AWS_SECRET_ACCESS_KEY=$(\
  cat keys/admin/*-creds | jq -r \
  '.AccessKey.SecretAccessKey')\"
echo \"-------------------------------\"

echo \"your monitoring and alerting portal uid/password :\" sysops:$BASIC_AUTH_PWD
echo \"\"

echo \"To login to grafana use below token with admin uid : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n metrics get secret grafana -o jsonpath=\"{.data.admin-password}\" | base64 --decode; echo
echo \"\"
echo \"\"
echo \"To login to kube dashboard use below token : it has an expiry so you will need to regenerate if its expired \"
echo \"\"
kubectl -n kube-system describe secret \$(kubectl -n kube-system get secret | grep admin-user-sa | awk '{print \$1}') | grep token:
echo \"\"
echo \"You can re-generate a token by running below command afer initial context setting \"
echo \"\"
echo \"-----------------------------\"
echo \"kubectl -n kube-system describe secret \$(kubectl -n kube-system get secret | grep admin-user-sa | awk '{print \$1}') | grep token: \"
echo \"-----------------------------\""> keys/admin/set-up-admin.sh

##----------------

####copy read me #####

cp README.md keys/test/README.md
cp README.md keys/dev/README.md
cp README.md keys/ops/README.md
cp README.md keys/admin/README.md

##########

####zip folders ####

zip -r keys/ops keys/ops
zip -r keys/test keys/test
zip -r keys/dev keys/dev
zip -r keys/admin keys/admin

####################
