#!/bin/bash

#### clean ssh key and iam key ####
#this script needs to be executed as admin
set -x
aws ec2 delete-key-pair --key-name kops

ACCESS_KEY_ID_KOPS=$(\
    cat keys/kops/kops-creds | jq -r \
    '.AccessKey.AccessKeyId')


aws iam delete-access-key --access-key $ACCESS_KEY_ID_KOPS --user-name kops

#######################

#### detach policies ####

aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
    --group-name kops
 
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --group-name kops
 
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
    --group-name kops
 
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
    --group-name kops
 
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess \
    --group-name kops

aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess \
    --group-name kops

aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AWSLambdaFullAccess \
    --group-name kops

aws iam delete-group-policy --policy-name kops-kms --group-name kops

############################

#### remove user from group ####

aws iam remove-user-from-group \
        --user-name kops \
        --group-name kops

################################

#### delete user and group #####

aws iam delete-user --user-name kops
        
aws iam delete-group --group-name kops

################################ 

##### delete temp files #######

rm -rf config
rm -rf k8s*
rm -rf keys
rm -rf *.temp.yaml

##############################
