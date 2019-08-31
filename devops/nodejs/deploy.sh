#!/bin/bash

# exit if there is a command with a non-sero status
set -e
# get current directory
THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -ne "\033]0; ${THIS_DIR##*/}\007" ## set the shell window title

# get base dir
BASE_DIR="$(cd "${THIS_DIR}/.." && pwd)"

# load validations and errors
. "${BASE_DIR}/so-lib.sh"

header NODE PRODUCTION

list-branches() {
    set -e
    echo "Listing branches..."

    rm -rf $1

    git clone $2

    cd $1

    git pull
    git branch -av | awk 'BEGIN {FS=" "} {gsub("*|refs/heads/|remotes/origin/", "")} {print $1}' > branches_clean.txt
    sort -u branches_clean.txt > branches_uniques.txt
    readarray BRANCHES_ARRAY < branches_uniques.txt

    # for branches array
    echo "-- Select branch to deploy to $1 --"
    for (( i=1; i<${#BRANCHES_ARRAY[@]}+1; i++ ));
    do
      echo -e "($i)" ${BRANCHES_ARRAY[$i-1]}
    done
    read SELECTED_ARRAY_BRANCH
    BRANCH_TO_DEPLOY=${BRANCHES_ARRAY[SELECTED_ARRAY_BRANCH-1]}
    git checkout $BRANCH_TO_DEPLOY
    cd ..

}

list-branches $AWS_COURSE_NAME_PROJECT $AWS_COURSE_GIT_REPOSITORY

#build number
if [ ! -f build-number ]; then
  echo 0 > build-number
fi

BUILD_NUMBER=`cat build-number`

# login to aws
export AWS_ACCESS_KEY_ID=$AWS_COURSE_AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_COURSE_AWS_SECRET_ACCESS_KEY
aws ecr get-login --no-include-email --region us-east-1 | sh

#CLOUD FORMATION
aws cloudformation create-stack --stack-name elb-node-prod-$BUILD_NUMBER --template-body https://public-aws-course-cicd-script.s3.amazonaws.com/node_prod_2019_07_14.json --parameters '
[
   {
      "ParameterKey": "AZs",
      "ParameterValue": "us-east-1d, us-east-1a"
   },
   {
      "ParameterKey": "InstanceCount",
      "ParameterValue": "2"
   },
   {
      "ParameterKey": "Subnets",
      "ParameterValue": "subnet-09956b30369a7c713, subnet-0cf3a8c9703dc2ca3"
   },
   {
      "ParameterKey": "VpcId",
      "ParameterValue": "vpc-02777bc8e193269b2"
   },
   {
      "ParameterKey": "KeyName",
      "ParameterValue": "ke_node_prod"
   },
   {
      "ParameterKey": "SSHLocation",
      "ParameterValue": "0.0.0.0/0"
   },
   {
      "ParameterKey": "InstanceType",
      "ParameterValue": "t2.micro"
   }
]'

echo $((BUILD_NUMBER + 1)) > build-number

build-docker() {
    #mkdir -f nodejs
    cp -R aws-course-cicd/src/nodejs nodejs
    cp -R web_docker/* nodejs
    aws ecr get-login --no-include-email --region=us-east-1 | sh
    docker build --build-arg APP_DOMAIN=$1 -t node-base nodejs
    docker tag node-base:latest 207155759131.dkr.ecr.us-east-1.amazonaws.com/node-prod-app:$BUILD_NUMBER
    docker push 207155759131.dkr.ecr.us-east-1.amazonaws.com/node-prod-app:$BUILD_NUMBER
    rm -fR aws-course-cicd
    rm -fR nodejs
}

build-docker PRODUCTION

build-cluster() {
  set -e
    #sleep 300
    aws ecs register-task-definition --family $1 --container-definitions "
    [
       {
          \"name\":\"app\",
          \"image\":\"207155759131.dkr.ecr.us-east-1.amazonaws.com/node-prod-app:$BUILD_NUMBER\",
          \"cpu\":256,
          \"memory\":256,
          \"essential\":true,
          \"portMappings\":[
             {
                \"containerPort\":80,
                \"hostPort\":80
             },
             {
                \"containerPort\":443,
                \"hostPort\":443
             }
          ],
          \"environment\":[
             {
              \"name\": \"conf\",
              \"value\": \"prod\"
              },
             {
                \"name\":\"env\",
                \"value\":\"prod\"
             }
          ]
       }
    ]" > revision.txt
    cat revision.txt

    rm -R Prod-*.txt
    cat revision.txt | grep revision | awk '{print $2}' | sed 's/,/ /g' > Prod-$BUILD_NUMBER.txt
    BUILD_REVISION=`cat Prod-$BUILD_NUMBER.txt`

    aws ecs update-service --cluster $1 --service node --task-definition $1:$BUILD_REVISION

    sleep 150
    aws cloudformation describe-stacks --stack-name elb-node-prod-$BUILD_NUMBER --output text | grep "URL" | awk '{print $7}' | sed 's/^.*\(elb-node*\)/\1/g' > url.txt

}

build-cluster node-prod

add-to-domain() {
  while sleep 1m
  do
    n_build=$((BUILD_NUMBER + 1))
    check=$(curl -k $(cat url.txt)/build-info )
    echo "New Build Number $n_build"
    echo "Running Build Number $check"
    if [[ "$n_build" == "$check" ]]; then
      aws route53 change-resource-record-sets --hosted-zone-id Z33VLSKLPO2P67 --change-batch "
        {
          \"Comment\": \"optional comment about the changes in this change batch request\",
          \"Changes\": [
            {
              \"Action\": \"UPSERT\",
              \"ResourceRecordSet\": {
                \"Name\": \"node-prod.atobcargo.com\",
                \"Type\": \"CNAME\",
                \"TTL\": 60,
                \"ResourceRecords\": [
                  {
                    \"Value\": \"$(cat url.txt)\"
                  }
                ]
              }
            }
          ]
        }
      "
      echo "Deployment Done"
      echo -e "\033[0;32mThe enviroment is done !!!  check here -> http://nodejs-prod.atobcargo.com\033[m"
      break
    else
      echo "Please wait for few more minutes, Ecs is deploying the code."
    fi
  done
}

add-to-domain

