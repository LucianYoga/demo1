#!/usr/bin/env bash

set -e

JQ="jq --raw-output --exit-status"

deploy_image() {
    # get the authorization code and login to aws ecr
    autorization_token=$(aws ecr get-authorization-token --registry-ids $account_id --output text --query authorizationData[].authorizationToken | base64 --decode | cut -d: -f2)
    docker login -u AWS -p $autorization_token -e none https://$account_id.dkr.ecr.us-east-1.amazonaws.com
    docker tag acmeinc/sample-api:$CIRCLE_SHA1 $account_id.dkr.ecr.us-east-1.amazonaws.com/sample-api:$CIRCLE_SHA1
    docker push $account_id.dkr.ecr.us-east-1.amazonaws.com/sample-api:$CIRCLE_SHA1
}

make_task_def() {
    task_template=$(cat ecs_taskdefinition.json)
    task_def=$(printf "$task_template" $CIRCLE_SHA1)
    echo "$task_def"
}

register_definition() {

    if revision=$(aws ecs register-task-definition --cli-input-json "$task_def" --family $family | $JQ '.taskDefinition.taskDefinitionArn'); then
        echo "Revision: $revision"
    else
        echo "Failed to register task definition"
        return 1
    fi

}

deploy_cluster() {


    make_task_def
    register_definition


    if [[ $(aws ecs update-service --cluster $cluster_name --service $service_name --task-definition $revision | \
                   $JQ '.service.taskDefinition') != $revision ]]; then
        echo "Error updating service."
        return 1
    fi

    for attempt in {1..30}; do
        if stale=$(aws ecs describe-services --cluster $cluster_name --services $service_name | \
                       $JQ ".services[0].deployments | .[] | select(.taskDefinition != \"$revision\") | .taskDefinition"); then
            echo "Waiting for stale deployments:"
            echo "$stale"
            sleep 5
        else
            echo "Deployed!"
            return 0
        fi
    done
    echo "Service update took too long."
    return 1

}

account_id=[aws_account_id]
family=acmeinc-api
service_name=acmeinc-api-srv

deploy_image
deploy_cluster
