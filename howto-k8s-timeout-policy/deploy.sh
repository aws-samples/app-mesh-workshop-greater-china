#!/bin/bash

set -eo pipefail

if [ -z $AWS_ACCOUNT_ID ]; then
    echo "AWS_ACCOUNT_ID environment variable is not set."
    exit 1
fi

if [ -z $AWS_DEFAULT_REGION ]; then
    echo "AWS_DEFAULT_REGION environment variable is not set."
    exit 1
fi

AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
PROJECT_NAME="howto-k8s-timeout-policy"
APP_NAMESPACE=${PROJECT_NAME}
MESH_NAME=${PROJECT_NAME}
CLOUDMAP_NAMESPACE="${PROJECT_NAME}.pvt.aws.local"

if [ $AWS_DEFAULT_REGION = "cn-northwest-1" ] ; then
    ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com.cn"
elif [ $AWS_DEFAULT_REGION = "cn-north-1" ] ; then
    ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com.cn"
else
    ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
fi
ECR_IMAGE_PREFIX="${ECR_URL}/${PROJECT_NAME}"
FRONT_APP_IMAGE="${ECR_IMAGE_PREFIX}/feapp"
COLOR_APP_IMAGE="${ECR_IMAGE_PREFIX}/colorapp"

MANIFEST_VERSION="${1:-v1beta2}"

error() {
    echo $1
    exit 1
}

check_virtualnode_v1beta2(){
    #check CRD
    crd=$(kubectl get crd virtualnodes.appmesh.k8s.aws -o json | jq -r '.. | .awsCloudMap?.properties.namespaceName? | select(. != null)')
    if [ -z "$crd" ]; then
        error "$PROJECT_NAME requires virtualnodes.appmesh.k8s.aws CRD to support Cloud Map service-discovery. See https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/master/CHANGELOG.md"
    else
        echo "CRD check passed!"
    fi
}

check_appmesh_k8s() {
    #check aws-app-mesh-controller version
    if [ "$MANIFEST_VERSION" = "v1beta2" ]; then
        currentver=$(kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1)
        requiredver="v1.0.0"
        check_virtualnode_v1beta2
    else
        error "$PROJECT_NAME unexpected manifest version input: $MANIFEST_VERSION. Timeouts are only supported in v1beta2 and AppMesh controller version >= v1.0.0. See https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/master/CHANGELOG.md"
    fi

    if [ "$(printf '%s\n' "$requiredver" "$currentver" | sort -V | head -n1)" = "$requiredver" ]; then
        echo "aws-app-mesh-controller check passed! $currentver >= $requiredver"
    else
        error "$PROJECT_NAME requires aws-app-mesh-controller version >=$requiredver but found $currentver. See https://github.com/aws/aws-app-mesh-controller-for-k8s/blob/master/CHANGELOG.md"
    fi
}

ecr_login() {
    if [ $AWS_CLI_VERSION -gt 1 ]; then
        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \
            docker login --username AWS --password-stdin ${ECR_URL}
    else
        $(aws ecr get-login --no-include-email)
    fi
}

deploy_images() {
    ecr_login
    for app in colorapp feapp; do
        aws ecr describe-repositories --repository-name $PROJECT_NAME/$app >/dev/null 2>&1 || aws ecr create-repository --repository-name $PROJECT_NAME/$app >/dev/null
        docker build -t ${ECR_IMAGE_PREFIX}/${app} ${DIR}/${app}
        docker push ${ECR_IMAGE_PREFIX}/${app}
    done
}

deploy_timeout_ns() {
    nsId=($(aws servicediscovery list-namespaces |
        jq -r ".Namespaces[] | select(.Name | contains(\"${CLOUDMAP_NAMESPACE}\")) | .Id"))

    if [ -z "${nsId}" ]; then
        if [ -z "${VPC_ID}" ]; then
            echo "VPC_ID must be set. VPC_ID corresponds to vpc where applications are deployed."
            exit 1
        fi

        aws servicediscovery create-private-dns-namespace \
            --name "${CLOUDMAP_NAMESPACE}" \
            --vpc "${VPC_ID}"
        echo "Created private-dns-namespace ${CLOUDMAP_NAMESPACE}"
        sleep 5
    fi
}

deploy_app() {
    EXAMPLES_OUT_DIR="${DIR}/_output/"
    mkdir -p ${EXAMPLES_OUT_DIR}
    eval "cat <<EOF
$(<${DIR}/${MANIFEST_VERSION}/manifest.yaml.template)
EOF
" >${EXAMPLES_OUT_DIR}/manifest.yaml

    kubectl apply -f ${EXAMPLES_OUT_DIR}/manifest.yaml
}

main() {
    check_appmesh_k8s

    deploy_timeout_ns

    if [ -z $SKIP_IMAGES ]; then
        echo "deploy images..."
        deploy_images
    fi

    deploy_app
}

main
