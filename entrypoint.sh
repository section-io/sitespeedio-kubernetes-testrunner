#! /bin/bash
test -z "${DEBUG}" || set -o xtrace

function active_job_exists() {

    job=$(kubectl get job sitespeedio --namespace "${SELF_NAMESPACE}" --output json &> /dev/null)
    [[ $? -eq 1 ]] && return 1 # If error job does not exist

    active=$(echo $job | jq '.status.active')
    [[ "${active}" == "null" ]] && return 1 # If `.status.active` is null then there is no active job

    return 0
}

while true; do

    # Poll for the job to finish before moving onto the next job
    while active_job_exists; do
        sleep 5
    done

    # Take a message from the queue
    response=$(redis-cli -h "${REDIS_HOST}" RPOPLPUSH "${QUEUE_NAME}" "${QUEUE_NAME}")
    message=$(echo "${response}" | tail -1)

    if [[ ! -z "${message}" ]]; then
        client_namespace=$(echo "${message}" | jq '.namespace' --raw-output)
        graphite_namespace=$(echo "${message}" | jq '.graphite_namespace' --raw-output)
        image=$(echo "${message}" | jq '.image' --raw-output)
        argarray=($(echo "${message}" | jq '.args[]' --raw-output))
        args=$(printf "        - %s\n" "${argarray[@]}")

        graphite_host_suffix=''
        if [[ "${client_namespace}" != 'null' ]]; then
            graphite_host_suffix=".${client_namespace}"
        fi

        # Delete the old job
        kubectl delete job sitespeedio --namespace "${SELF_NAMESPACE}" || echo "Job doesn't exist"

        # Create a new job
        graphite_host_suffix="${graphite_host_suffix}" graphite_namespace="${graphite_namespace}" args="${args}" image="${image}" envsubst < /sitedeployment.yml.template | kubectl apply --namespace "${SELF_NAMESPACE}" -f -
    fi
done
