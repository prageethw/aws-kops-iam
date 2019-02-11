#!/bin/bash
set -x
####### create group and assign policies ######
###kops group
aws iam create-group --group-name kops

###kops group policy attach
aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AWSLambdaFullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess \
    --group-name kops

################################################

####### create user and assign to the group ######
###----- kops user ----
aws iam create-user \
    --user-name kops


#wait till user really created
aws  iam  wait --user-name user-exists kops


### add user to group
aws iam add-user-to-group \
    --user-name kops \
    --group-name kops

###############################################

####### generate iam credentials specific for kops #######
mkdir -p keys/kops
aws iam create-access-key \
    --user-name kops >keys/kops/kops-creds

###############################################

WAIT_USER_KEY_CREATION=10

echo "Sleeping for $WAIT_USER_KEY_CREATION secs till all resources created ..."

sleep $WAIT_USER_KEY_CREATION

####### set terminal to use new kops iam ######

export AWS_ACCESS_KEY_ID=$(\
    cat keys/kops/kops-creds | jq -r \
    '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(
    cat keys/kops/kops-creds | jq -r \
    '.AccessKey.SecretAccessKey')

###############################################

##### generate ssh keys ##########

aws ec2 create-key-pair \
--key-name kops \
| jq -r '.KeyMaterial' \
>keys/kops/kops.pem

chmod 400 keys/kops/kops.pem

ssh-keygen -y -f keys/kops/kops.pem \
    >keys/kops/kops.pub

###################################
