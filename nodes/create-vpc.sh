#!/bin/bash
set -e

#https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html
#https://medium.com/@brad.simonin/create-an-aws-vpc-and-subnet-using-the-aws-cli-and-bash-a92af4d2e54b

NAME="Bioland"
REGION=$1

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

#Check Exists:
VPC_COUNT=$(aws --region "$REGION" ec2 describe-vpcs --filters Name=tag:Name,Values="$NAME VPC" | jq ".Vpcs|length")

if [ "$VPC_COUNT" -ne "0" ]
then

  echo "$NAME VPC alreary exists"
  
  VPC_ID=$(aws            --region "$REGION" ec2 describe-vpcs              --filters Name=tag:Name,Values="$NAME VPC"          | jq --raw-output ".Vpcs[0].VpcId")
  SUBNET_ID=$(aws         --region "$REGION" ec2 describe-subnets           --filters Name=tag:Name,Values="$NAME Subnet"       | jq --raw-output ".Subnets[0].SubnetId")
  GATEWAY_ID=$(aws        --region "$REGION" ec2 describe-internet-gateways --filters Name=tag:Name,Values="$NAME Gateway"      | jq --raw-output ".InternetGateways[0].InternetGatewayId")
  ROUTE_TABLE_ID=$(aws    --region "$REGION" ec2 describe-route-tables      --filters Name=tag:Name,Values="$NAME Route Table"  | jq --raw-output ".RouteTables[0].RouteTableId")
  SECURITY_GROUP_ID=$(aws --region "$REGION" ec2 describe-security-groups   --filters Name=tag:Name,Values="$NAME Security"     | jq --raw-output ".SecurityGroups[0].GroupId")

else

  echo "$NAME VPC do not exists. Createing...."

  VPC_ID=$(aws --region "$REGION" ec2 create-vpc  --cidr-block 10.100.0.0/16 | jq --raw-output ".Vpc.VpcId" )
           aws --region "$REGION" ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="$NAME VPC"
  
  GATEWAY_ID=$(aws --region "$REGION" ec2 create-internet-gateway | jq --raw-output ".InternetGateway.InternetGatewayId" )
               aws --region "$REGION" ec2 create-tags             --resources "$GATEWAY_ID" --tags Key=Name,Value="$NAME Gateway"
               aws --region "$REGION" ec2 attach-internet-gateway --internet-gateway-id "$GATEWAY_ID" --vpc-id "$VPC_ID" 
  
  SUBNET_ID=$(aws --region "$REGION" ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.100.0.0/24 | jq --raw-output ".Subnet.SubnetId" )
              aws --region "$REGION" ec2 create-tags   --resources "$SUBNET_ID" --tags Key=Name,Value="$NAME Subnet"
              aws --region "$REGION" ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch
  
  SECURITY_GROUP_ID=$(aws --region "$REGION" ec2 create-security-group  --group-name "$NAME Security"   --description "$NAME Security FW rules" --vpc-id "$VPC_ID" |  jq --raw-output ".GroupId" )
                      aws --region "$REGION" ec2 create-tags            --resources "$SECURITY_GROUP_ID" --tags Key=Name,Value="$NAME Security"
                      aws --region "$REGION" ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port  22 --cidr 0.0.0.0/0
                      aws --region "$REGION" ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port  80 --cidr 0.0.0.0/0
                      aws --region "$REGION" ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0
  
  ROUTE_TABLE_ID=$(aws --region "$REGION" ec2 create-route-table      --vpc-id "$VPC_ID" |  jq --raw-output ".RouteTable.RouteTableId" )
                   aws --region "$REGION" ec2 create-tags             --resources "$ROUTE_TABLE_ID" --tags Key=Name,Value="$NAME Route Table"
                   aws --region "$REGION" ec2 create-route            --route-table-id "$ROUTE_TABLE_ID" --gateway-id "$GATEWAY_ID" --destination-cidr-block 0.0.0.0/0
  ASSOCISTION_ID=$(aws --region "$REGION" ec2 associate-route-table   --route-table-id "$ROUTE_TABLE_ID" --subnet-id  "$SUBNET_ID" |  jq --raw-output ".AssociationId" ) 

  echo "VPC created"
fi


echo " "
echo "vpc-id:              $VPC_ID"
echo "subnet-id:           $SUBNET_ID"
echo "security-group-id:   $SECURITY_GROUP_ID"
echo "internet-gateway-id: $GATEWAY_ID"
echo "route-table-id:      $ROUTE_TABLE_ID"
echo " "
