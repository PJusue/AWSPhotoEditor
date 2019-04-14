#!/bin/bash

MAGENTA='\033[1;35m'
NONE='\033[0m'

INSTANCES_IDS=$(aws ec2 describe-instances|grep -i instances | awk '{print $8}')
aws ec2 terminate-instances --instance-ids $INSTANCES_IDS
echo "Waiting for the instances to terminate..."
aws ec2 wait instance-terminated --instance-ids $INSTANCES_IDS
sleep 3
echo -e "${MAGENTA} Instances ${INSTANCES_IDS} terminated ${NONE}"
sleep 5
KEY_PAIRS=$(aws ec2 describe-key-pairs|awk '{print $3}')
for KEY_PAIR in $KEY_PAIRS
do
aws ec2 delete-key-pair --key-name $KEY_PAIR
done
LOAD_BALANCERS=$(aws elb describe-load-balancers|grep LOADBALANCER|awk '{print $6}')
for LOAD_BALANCER in $LOAD_BALANCERS
do
 aws elb delete-load-balancer --load-balancer-name $LOAD_BALANCER
done
echo  -e "${MAGENTA} Load-balancers $LOAD_BALANCERS deleted ${NONE}"
echo "Deleting all the .priv files"
sudo rm *.priv
echo -e "${MAGENTA} All files deleted ${NONE}"
BUCKETS=$(aws s3api list-buckets|grep -i Buckets|awk '{print $3}')
for BUCKET in $BUCKETS
do
aws s3 rb s3://$BUCKET --force
done
QUEUES_URL=$(aws sqs list-queues|awk '{print $2}')
aws sqs delete-queue --queue-url $QUEUES_URL