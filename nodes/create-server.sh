#!/bin/bash
set -e

NAME="Bioland"
REGION=$1

# Validate Regions

if [ -z "$REGION" ]
then
  echo "Region not passed"
  exit -1
fi

if [ "$REGION" != "us-east-1" ]
then
  echo "Only us-east-1 region is supported"
  exit -1
fi

# Test server Exists

VM_LIST=$(aws --region "$REGION" ec2 describe-instances --filters Name=tag:Name,Values="$NAME Server" | jq --raw-output ".Reservations[0]") 
VM=$(echo $VM_LIST | jq --raw-output ".Instances[0]")

if [ "$(echo $VM_LIST | jq --raw-output ".Instances|length")" -ne "0" ]
then
  echo "$NAME Server alreary exists"
  echo "Instance-Id: $(echo $VM | jq --raw-output ".InstanceId")"
  echo "Instance:    $(echo $VM | jq              ".Tags[]|select(.Key==\"Name\").Value")"
  echo "Public  IP:  $(echo $VM | jq --raw-output ".PublicIpAddress")"
  exit 0
fi

# Load server image (AMI) => Ubuntu, 18.04 LTS,

AMI="null"
if [ "$REGION" == "us-east-1" ]
then
  AMI=$(aws --region "$REGION" ec2 describe-images --image-ids ami-0ac019f4fcb7cb7e6)
fi

if [ "$AMI" == "null" ]
then 
  echo "ERROR No ami defines fo the Region: $REGION"
  exit -3 
fi

AMI_ID=$(echo      $AMI | jq --raw-output ".Images[0].ImageId");
AMI_DESC=$(echo    $AMI | jq --raw-output ".Images[0].Description");
AMI_SNAP_ID=$(echo $AMI | jq --raw-output ".Images[0].BlockDeviceMappings[0].Ebs.SnapshotId");

# Load Network information

SECURITY_GROUP_ID=$(aws --region "$REGION" ec2 describe-security-groups   --filters Name=tag:Name,Values="$NAME Security" | jq --raw-output ".SecurityGroups[0].GroupId")

if [ "$SECURITY_GROUP_ID" == "null" ]
then 
  echo "ERROR Security groups not found" 
  exit -3 
fi

SUBNET=$(aws --region "$REGION" ec2 describe-subnets  --filters Name=tag:Name,Values="$NAME Subnet"   | jq --raw-output ".Subnets[0]")
SUBNET_ID=$(echo         $SUBNET | jq --raw-output ".SubnetId")
AVAILABILITY_ZONE=$(echo $SUBNET | jq --raw-output ".AvailabilityZone")

echo "availability-zone:   $AVAILABILITY_ZONE"
echo "subnet-id:           $SUBNET_ID"
echo "security-group-id:   $SECURITY_GROUP_ID"

if [ "$SUBNET_ID" == "null" ]
then 
  echo "ERROR Subnet not found" 
  exit -3 
fi

# Load/Create Bioland Data volume

VOLUME_ID=$(aws --region "$REGION" ec2 describe-volumes  --filters Name=tag:Name,Values="$NAME Data" | jq --raw-output ".Volumes[0].VolumeId");

if [ "$VOLUME_ID" == "null" ]
then
  
  # Create a static volume based on an ext4 FS

  SNAPSHOT_ID=$(aws --region "$REGION" ec2 describe-snapshots --filters Name=tag:Name,Values="ext4-fs" | jq --raw-output ".Snapshots[0].SnapshotId");

  if [ "$SNAPSHOT_ID" == "null" ]
  then 
    echo "ERROR EXT4 Filesystem snapshot not found to create $NAME data volum" 
    exit -4
  fi

  echo Create volume "$NAME Data"

  VOLUME_ID=$(aws --region "$REGION" ec2 create-volume --size 80 --snapshot-id $SNAPSHOT_ID --availability-zone $AVAILABILITY_ZONE --volume-type gp2 --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=\"$NAME Data\"}]" | jq --raw-output ".VolumeId")
fi

echo "Volume-Id: $VOLUME_ID"

# create Server

echo "Create server"
echo "ami-id: $AMI_ID" 
echo "ami:    $AMI_DESC"

RES=$(aws --region "$REGION" ec2 run-instances          \
  --image-id $AMI_ID                                    \
  --region "$REGION"                                    \
  --user-data file://cloud-config-$REGION.yml           \
  --instance-type t2.medium                             \
  --disable-api-termination                             \
  --security-group-ids $SECURITY_GROUP_ID               \
  --subnet-id $SUBNET_ID                                \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=\"$NAME Server\"}]" \
  --block-device-mappings "[                            \
      {                                                 \
        \"DeviceName\":\"/dev/sda1\",                   \
        \"Ebs\": {                                      \
          \"SnapshotId\":\"$AMI_SNAP_ID\",              \
          \"VolumeSize\":40,                            \
          \"VolumeType\":\"gp2\",                       \
          \"DeleteOnTermination\":true                  \
        }                                               \
      }                                                 \
    ]")

INSTANCE_ID=$(echo $RES | jq --raw-output ".Instances[0].InstanceId")

if [ "$INSTANCE_ID" == "null" ]
  then 
    echo "ERROR Creating server" 
    echo $RES
    exit -4
  fi

echo "Instance-Id: $INSTANCE_ID"

# wait for instance to bea ready 
INSTANCE_STATE="pending"

while [ "$INSTANCE_STATE" == "pending" ]
do
  echo "Waiting 10s for VM to start..."
  sleep 10 
  INSTANCE_STATE=$(aws --region "$REGION" ec2 describe-instances --instance-ids $INSTANCE_ID | jq --raw-output ".Reservations[0].Instances[0].State.Name")
done

echo "Instance Public IP:  $(aws --region "$REGION" ec2 describe-instances --instance-ids $INSTANCE_ID | jq --raw-output ".Reservations[0].Instances[0].PublicIpAddress")"


# ATTACHE VOLUME 

echo "Attaching volume to VM..."
echo AttachTime: $(aws --region "$REGION" ec2 attach-volume --device "/dev/xvdk" --instance-id $INSTANCE_ID --volume-id $VOLUME_ID | jq --raw-output ".AttachTime")


