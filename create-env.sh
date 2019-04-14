#!/bin/bash
#COLORS
MAGENTA='\033[1;35m'
NONE='\033[0m'
#VARIABLES
PORTS_TO_ENABLE=( 22 5000 80 11211 )
CIDR="0.0.0.0/0"
PROTOCOL="tcp"
AVAILABILITY_ZONE1="us-west-2b"
BUCKET_REGION="us-east-1"
PERMISSIONS="public-read"
AVAILABILITY_ZONE2="us-west-2a"
DATABASE_SECURITY_GROUP_NAME="dBSecurityGroup"
DATABASE_SECURITY_GROUP_DESCRIPTION="Database security group"
BUCKET_NAME="pjfimages-bucket"
DATABASE_NAME="mp2dbinstance"
DATABASE_REPLICA_NAME="mp2dbinstancereplica"
QUEUE_NAME="MP2queue"
clear
echo "*********************************************************************"
echo -e "${MAGENTA}This script performs all the MP2 requirements. "
echo -e "Script written by Pablo Jusue Fernandez for the ITMO 544 class at the IIT"
echo -e "E-mail: pjusue@hawk.iit.edu ${NONE}"
echo "*********************************************************************"

if [ "$1" = "" ];then
        echo -e "${MAGENTA}The user has not use a positional parameter to generate the instances it will be used the default one ${NONE}"
        INSTANCE_AMI=ami-06bae0351181dee00
else
        INSTANCE_AMI=$1
fi
echo "Are you going to create a new security group(Y/N)?"
read OPTION
OPTION=$(echo $OPTION|tr '[:lower:]' '[:upper:]')
if      [ "$OPTION" == "Y" ]
then
        echo "Introduce your security group name"
        read NAME
        echo "Creating a new security group..."
        SECURITY_GROUP_ID=$(aws ec2 create-security-group --description "This is for ITMO 544" --group-name $NAME)
        for PORT in "${PORTS_TO_ENABLE[@]}"
        do
        echo -e "${MAGENTA}Port ${PORT} opened ${NONE}"
        aws ec2 authorize-security-group-ingress --group-name $NAME --protocol $PROTOCOL --port $PORT --cidr $CIDR
        done
elif    [ "$OPTION" == "N" ]
then
        echo "Introduce your security group name"
        read NAME
        SECURITY_GROUP_ID=$(aws ec2 describe-security-groups|grep $NAME|cut -f2 -d'-'|awk -F ${NAME} '{print $1}')
        SECURITY_GROUP_ID=sg-$SECURITY_GROUP_ID
        for PORT in "${PORTS_TO_ENABLE[@]}"
        do
        aws ec2 authorize-security-group-ingress --group-name $NAME --protocol $PROTOCOL --port $PORT --cidr $CIDR 2>>/dev/null 1>>/dev/null
        done
fi
echo "Are you going to create a new key (Y/N)?"
read OPTION
OPTION=$(echo $OPTION |tr '[:lower:]' '[:upper:]')
if      [ "$OPTION" == "N" ]
then
        echo "Introduce your old key file name"
        read KEY
elif    [ "$OPTION" == "Y" ];
then
        echo "Introduce your new key file name "
        read KEY
        echo "Creating the key..."
        aws ec2 create-key-pair --key-name $KEY --query 'KeyMaterial' --output text >$KEY.priv
        echo -e "${MAGENTA} Key created succesfully ${NONE}"
        chmod 400 $KEY.priv
fi
#echo "Introduce the number of instances"
#read COUNT
QUEUE_URL=$(aws sqs create-queue --queue-name $QUEUE_NAME)
echo -e "${MAGENTA} Created the queue $QUEUE_URL ${NONE}"
echo  "Creating the security group of the database..."
DB_SG_ID=$(aws ec2 create-security-group --group-name $DATABASE_SECURITY_GROUP_NAME --description "Database security groups")
if      [ "$DB_SG_ID" == "" ]
then
        DB_SG_ID=$(aws ec2 describe-security-groups|grep dBSecurityGroup| cut -f2 -d '-' |awk '{print $1}')
        DB_SG_ID=sg-$DB_SG_ID
fi
aws elasticache create-cache-cluster --cache-cluster-id memcachemp3pjf --engine memcached --cache-node-type cache.t2.micro --preferred-availability-zone us-west-2b  --port 11211 --num-cache-nodes 1
echo -e "${MAGENTA} Created the database security group${NONE}"
aws ec2 authorize-security-group-ingress --group-name $DATABASE_SECURITY_GROUP_NAME --protocol tcp --port 3306 --cidr $CIDR 2>>/dev/null
echo "Creating the database..."
DB_ID=$(aws rds create-db-instance --db-instance-identifier $DATABASE_NAME --allocated-storage 20 --vpc-security-group-ids $DB_SG_ID --db-instance-class db.t2.micro --engine mysql --master-username pjusue --master-user-password mp2pjusue --availability-zone us-west-2b 2>>/dev/null)
aws rds wait db-instance-available --db-instance-identifier $DATABASE_NAME
echo -e "${MAGENTA} Databased created ${NONE}"
#MP3 read replica
echo  "Creating a read-replica from the database"
DB_REPLICA_ID=$(aws rds create-db-instance-read-replica --db-instance-identifier $DATABASE_REPLICA_NAME --source-db-instance-identifier $DATABASE_NAME)
aws rds wait db-instance-available --db-instance-identifier $DATABASE_REPLICA_NAME
echo -e "${MAGENTA} Replica $DATABASE_REPLICA_NAME created from $DATABASE_NAME ${NONE}"
cp MP2.json $NAME.json
aws iam create-role --role-name $NAME --assume-role-policy-document file://$NAME.json 2>> /dev/null
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/PowerUserAccess --role-name $NAME 2>> /dev/null
aws iam create-instance-profile --instance-profile-name $NAME
aws iam add-role-to-instance-profile --role-name $NAME --instance-profile-name $NAME
echo "Waiting for the instance profile"
aws iam wait instance-profile-exists --instance-profile-name $NAME
sleep 7
aws s3api create-bucket --bucket $BUCKET_NAME  --acl "public-read" --create-bucket-configuration LocationConstraint=us-west-2
#INSTANCES_IDS=$(aws ec2 run-instances --image-id $INSTANCE_AMI  --count $COUNT --instance-type t2.micro  --iam-instance-profile Name="$NAME" --key-name $KEY  --security-groups $NAME  --placement "AvailabilityZone=us-west-2b" --user-data file://create-app.sh  |grep -i instances|awk '{print $7}')
#echo -e "${MAGENTA} The IDs od the instances created are: $INSTANCES_IDS ${NONE}"
INSTANCE_ID_BACKEND2=$(aws ec2 run-instances --image-id $INSTANCE_AMI --count 1 --instance-type t2.micro --iam-instance-profile Name="$NAME" --key-name $KEY --security-groups $NAME      --placement "AvailabilityZone=us-west-2b" --user-data file://create-backend2.sh |grep -i instances|awk '{print $7}')
echo "Waiting to the instance to initialize..."
aws ec2 wait instance-status-ok --instance-id $INSTANCES_IDS
echo "Introduce the load balancer name"
read LOAD_BALANCER_NAME
aws elb create-load-balancer --load-balancer-name $LOAD_BALANCER_NAME --listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" "Protocol=HTTP,LoadBalancerPort=5000,InstanceProtocol=HTTP,InstancePort=5000" --availability-zones $AVAILABILITY_ZONE1 --security-groups $SECURITY_GROUP_ID
#aws elb register-instances-with-load-balancer --load-balancer-name $LOAD_BALANCER_NAME --instances  $INSTANCES_IDS
aws elb create-lb-cookie-stickiness-policy --load-balancer-name $LOAD_BALANCER_NAME --policy-name stickiness-policy
aws elb set-load-balancer-policies-of-listener --load-balancer-name $LOAD_BALANCER_NAME --load-balancer-port 5000 --policy-names stickiness-policy
echo -e "${MAGENTA} Load Balancer $LOAD_BALANCER_NAME created and stickiness-policy attached ${NONE}"
#MP2
echo "Waiting to the instance to initialize..."
#aws ec2 wait instance-status-ok --instance-id $INSTANCE_ID_BACKEND2
echo -e "${MAGENTA} The IDs od the instances created are: $INSTANCE_ID_BACKEND2 ${NONE}"
aws autoscaling create-launch-configuration --launch-configuration-name my-launch-config --image-id $INSTANCE_AMI --instance-type t2.micro --iam-instance-profile $NAME --key-name $KEY  --security-groups $NAME --user-data file://create-app.sh
aws autoscaling create-auto-scaling-group --auto-scaling-group-name my-auto-scaling-group --launch-configuration-name my-launch-config --load-balancer-names $LOAD_BALANCER_NAME --health-check-type ELB --health-check-grace-period 120 --min-size 1 --max-size 6 --desired-capacity 3 --availability-zone us-west-2b





