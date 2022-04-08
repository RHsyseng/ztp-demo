#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit
set -m

function check_vars() {
    var_names=("$@")
    var_unset=''
    for var_name in "${var_names[@]}"; do
        [[ -z "${!var_name}" ]] && echo "$var_name is unset. Please fill it in ${BASEDIR}/config/env file" && var_unset=true
    done
    [[ -n "${var_unset}" ]] && exit 1

    return 0
}

function render_file() {
    SOURCE_FILE=${1}
    if [[ $# -lt 1 ]]; then
        echo "Usage :"
        echo "  $0 <SOURCE FILE> <(optional) DESTINATION_FILE>"
        exit 1
    fi

    DESTINATION_FILE=${2:-""}
    ready=false
    if [[ ${DESTINATION_FILE} == "" ]]; then
        for try in seq {0..10}; do
            envsubst <${SOURCE_FILE} | oc --kubeconfig=${KUBECONFIG} apply -f -
            if [[ $? == 0 ]]; then
                ready=true
                break
            fi
            echo "Retrying the File Rendering (${try}/10): ${SOURCE_FILE}"
            sleep 5
        done
    else
        envsubst <${SOURCE_FILE} >${DESTINATION_FILE}
    fi
}

function check_resource() {
    # 1 - Resource type: "deployment"
    # 2 - Resource name: "openshift-pipelines-operator"
    # 3 - Type Status: "Available"
    # 4 - Namespace: "openshift-operators"

    if [[ -z ${1} ]]; then
        echo "I need a resource to check, value passed: \"${1}\""
        exit 1
    fi

    if [[ -z ${2} ]]; then
        echo "I need a resource name to check, value passed: \"${2}\""
        exit 1
    fi

    if [[ -z ${3} ]]; then
        echo "I need a Type Status (E.G 'Available') from status.conditions json field to check, value passed: \"${3}\""
        exit 1
    fi

    if [[ -z ${4} ]]; then
        echo "I need a Namespace to check the resource into, value passed: \"${4}\""
        exit 1
    fi

    RESOURCE="${1}"
    RESOURCE_NAME="${2}"
    TYPE_STATUS="${3}"
    NAMESPACE="${4}"

    echo ">>>> Checking Resource: ${RESOURCE} with name ${RESOURCE_NAME}"
    timeout=0
    ready=false
    while [ "$timeout" -lt "1000" ]; do
        if [[ $(oc --kubeconfig=${KUBECONFIG} -n ${NAMESPACE} get ${RESOURCE} ${RESOURCE_NAME} -o jsonpath="{.status.conditions[?(@.type==\"${TYPE_STATUS}\")].status}") == 'True' ]]; then
            ready=true
            break
        fi
        echo "Waiting for ${RESOURCE} ${RESOURCE_NAME} to change the status to ${TYPE_STATUS}"
        sleep 20
        timeout=$((timeout + 1))
    done

    if [ "$ready" == "false" ]; then
        echo "Timeout waiting for ${RESOURCE}-${RESOURCE_NAME} to change the status to ${TYPE_STATUS}"
        exit 1
    fi
}

function check_crd_group() {

	if [[ -z ${1} ]];then
		echo "I need a Pattern to look for into the Hub CRDs"
		exit 1
	fi

	pattern=${1}

	declare -a CRDS=()
	for CRD in $(oc get crd | grep ${pattern} | cut -f1 -d\ | tr '\n' ' ')
	do 
		check_resource "crd" "${CRD}" "Established" "openshift-operators"
	done
}

function validate_hub() {

	# Validate Environment
	echo ">> Checking Hub resources: RHACM - CRDs"
	echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
	check_crd_group "open-cluster-management"
	echo

	echo ">> Checking Hub resources: ArgoCD - CRDs"
	echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
	check_crd_group "argoproj"
	echo

	echo ">> Checking Hub resources: RHACM - Deployments"
	echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
	declare -a Dep=("cluster-manager" "hive-operator" "infrastructure-operator" "discovery-operator" "assisted-service" "managedcluster-import-controller-v2" "ocm-controller")
	for dep in ${Dep[@]}; do
	    check_resource "deployment" "${dep}" "Available" "open-cluster-management"
	done
	echo

	echo ">> Checking Hub resources: ArgoCD - Deployments"
	echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
	declare -a Dep=("cluster" "kam" "openshift-gitops-applicationset-controller" "openshift-gitops-dex-server" "openshift-gitops-redis" "openshift-gitops-repo-server" "openshift-gitops-server")
	for dep in ${Dep[@]}; do
	    check_resource "deployment" "${dep}" "Available" "openshift-gitops"
	done
	echo

}

function prepare_env() {
	source ${BASEDIR}/config/env

	# Validate Variables
	check_vars SPOKE_NAMESPACE BMH_USERNAME BMH_PASSWORD PULL_SECRET_PATH KUBECONFIG
	export PULL_SECRET_STRING=\'$(cat ${PULL_SECRET_PATH} | jq -c)\'
	export BMH_USERNAME=$(echo -n ${BMH_USERNAME} | base64)
	export BMH_PASSWORD=$(echo -n ${BMH_PASSWORD} | base64)
}

export BASEDIR=$(dirname "${0}")
export REPODIR=${BASEDIR}/..
export TMP_DIR=${REPODIR}/out
export VAL="${1:-}"

prepare_env

if [[ "${VAL}" == "validate" ]];then
	validate_hub
fi

for NS in "${SPOKE_NAMESPACE}" 'edge-sno-02' 'rh-lab'
do
	export NAMESPACE=${NS}
	echo ">> Rendering assets for ${NAMESPACE} in ${TMP_DIR}/${NAMESPACE}"
	mkdir -p ${TMP_DIR}/${NAMESPACE}
	render_file ${BASEDIR}/config/namespace-template.yaml ${TMP_DIR}/${NAMESPACE}/${NAMESPACE}-ns.yaml 
	render_file ${BASEDIR}/config/bmh-secret-template.yaml ${TMP_DIR}/${NAMESPACE}/${NAMESPACE}-bmh-secret.yaml 
	render_file ${BASEDIR}/config/pull-secret-template.yaml ${TMP_DIR}/${NAMESPACE}/${NAMESPACE}-pull-secret.yaml 
	oc apply -f ${TMP_DIR}/${NAMESPACE}/${NAMESPACE}-ns.yaml
	oc apply -f ${TMP_DIR}/${NAMESPACE}
	echo ">> Done!" 
	echo
done

