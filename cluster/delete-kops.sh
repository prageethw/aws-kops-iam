#!/bin/bash
set -x
source ./k8s-kops-cluster.temp
#### delete cluster with $NAME  and s3 bucket ####

kops delete cluster \
    --name $NAME \
    --yes

aws s3api delete-bucket \
    --bucket $BUCKET_NAME

aws acm delete-certificate \
    --certificate-arn $AWS_SSL_CERT_ARN

##delete Roles
aws iam delete-role --role-name kops-dev
aws iam delete-role --role-name kops-test
aws iam delete-role --role-name kops-ops
aws iam delete-role --role-name kops-admin

## DELETE policy
aws iam delete-group-policy --policy-name kops-dev --group-name kops-dev
aws iam delete-group-policy --policy-name kops-test --group-name kops-test
aws iam delete-group-policy --policy-name kops-ops --group-name kops-ops
aws iam delete-group-policy --policy-name kops-admin --group-name kops-admin

# delete users from group
aws iam remove-user-from-group \
    --user-name kops-dev \
    --group-name kops-dev
    
aws iam remove-user-from-group \
    --user-name kops-test \
    --group-name kops-test
    
aws iam remove-user-from-group \
    --user-name kops-ops \
    --group-name kops-ops
    
aws iam remove-user-from-group \
    --user-name kops-admin \
    --group-name kops-admin

# delete creds
ACCESS_KEY_ID_DEV=$(\
    cat keys/dev/kops-dev-creds | jq -r \
    '.AccessKey.AccessKeyId')
aws iam delete-access-key --access-key $ACCESS_KEY_ID_DEV --user-name kops-dev
ACCESS_KEY_ID_TEST=$(\
    cat keys/test/kops-test-creds | jq -r \
    '.AccessKey.AccessKeyId')
aws iam delete-access-key --access-key $ACCESS_KEY_ID_TEST --user-name kops-test
ACCESS_KEY_ID_OPS=$(\
    cat keys/ops/kops-ops-creds | jq -r \
    '.AccessKey.AccessKeyId')
aws iam delete-access-key --access-key $ACCESS_KEY_ID_OPS --user-name kops-ops
ACCESS_KEY_ID_ADMIN=$(\
    cat keys/admin/kops-admin-creds | jq -r \
    '.AccessKey.AccessKeyId')
aws iam delete-access-key --access-key $ACCESS_KEY_ID_ADMIN --user-name kops-admin

# delete user groups
aws iam delete-group --group-name kops-dev
aws iam delete-group --group-name kops-test
aws iam delete-group --group-name kops-ops
aws iam delete-group --group-name kops-admin

# delete users
aws iam delete-user --user-name kops-dev
aws iam delete-user --user-name kops-test
aws iam delete-user --user-name kops-ops
aws iam delete-user --user-name kops-admin


#############################

