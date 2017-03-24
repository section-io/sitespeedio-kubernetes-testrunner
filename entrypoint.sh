#! /bin/bash

while true; do
    response=$(redis-cli -h redis.section-sitespeed RPOPLPUSH queue queue)
    message=$(echo "${response}" | tail -1)

    namespace=$(echo "${message}" | jq '.namespace' --raw-output)
    image=$(echo "${message}" | jq '.image' --raw-output)
    argarray=($(echo "${message}" | jq '.args[]' --raw-output))
    args=$(printf "        - %s\n" "${argarray[@]}")

    # Check if this namespace has an active job already
    active=$(kubectl get job sitespeedio --namespace "${namespace}" --output json | jq '.status.active')
    if [[ "${active}" == 'null' ]]; then

        # Delete the old job
        kubectl delete job sitespeedio --namespace "${namespace}" || echo "Job doesn't exist"

        # Create a new job
        namespace="${namespace}" args="${args}" image="${image}" envsubst < /sitedeployment.yml.template | kubectl apply -f -
        active=1

        # Poll for the job to finish before moving onto the next job
        while [[ "${active}" == 1 ]]; do
            sleep 5
            active=$(kubectl get job sitespeedio --namespace "${namespace}" --output json | jq '.status.active')
        done
    fi
done
