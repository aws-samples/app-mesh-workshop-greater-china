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
PROJECT_NAME="howto-k8s-egress"
APP_NAMESPACE=${PROJECT_NAME}
MESH_NAME=${PROJECT_NAME}

if [ $AWS_DEFAULT_REGION = "cn-northwest-1" ] ; then
    ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com.cn"
    ECR_IMAGE_PREFIX="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com.cn/${PROJECT_NAME}"
elif [ $AWS_DEFAULT_REGION = "cn-north-1" ] ; then
    ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com.cn"
    ECR_IMAGE_PREFIX="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com.cn/${PROJECT_NAME}"
else
    ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
    ECR_IMAGE_PREFIX="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${PROJECT_NAME}"
fi

FRONT_APP_IMAGE="${ECR_IMAGE_PREFIX}/feapp"
COLOR_APP_IMAGE="${ECR_IMAGE_PREFIX}/colorapp"
MANIFEST_VERSION="${1:-v1beta2}"

error() {
    echo $1
    exit 1
}

check_appmesh_k8s() {
    #check aws-app-mesh-controller version
    currentver=$(kubectl get deployment -n appmesh-system appmesh-controller -o json | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'|tail -n1)
    requiredver="v1.0.0"

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

    if [ -z $SKIP_IMAGES ]; then
        echo "deploy images..."
        deploy_images
    fi

    deploy_app
}

main
