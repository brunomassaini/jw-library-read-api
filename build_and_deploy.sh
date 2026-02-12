#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${APP_NAME:=jw-library-read-api}"
: "${DOCKER_REPOSITORY:=brunomassaini}"
: "${IMAGE_TAG:=latest}"
: "${DOCKER_PLATFORM:=linux/amd64}"
: "${NAMESPACE:=default}"
: "${K8S_DIR:=${SCRIPT_DIR}/k8s}"
: "${KUBECTL_BIN:=kubectl}"
: "${KUBECONFIG:=}"
: "${KUBE_CONTEXT:=}"
: "${RUN_API_KEY_SETUP:=true}"

if [[ -n "${KUBECONFIG}" ]]; then
  export KUBECONFIG
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH." >&2
  exit 1
fi

if ! command -v "${KUBECTL_BIN}" >/dev/null 2>&1; then
  echo "kubectl not found: ${KUBECTL_BIN}" >&2
  exit 1
fi

if [[ ! -d "${K8S_DIR}" ]]; then
  echo "Kubernetes manifests directory not found: ${K8S_DIR}" >&2
  exit 1
fi

FULL_IMAGE="${DOCKER_REPOSITORY}/${APP_NAME}:${IMAGE_TAG}"
kubectl_base=("${KUBECTL_BIN}")
if [[ -n "${KUBE_CONTEXT}" ]]; then
  kubectl_base+=("--context" "${KUBE_CONTEXT}")
fi

docker build --platform "${DOCKER_PLATFORM}" -t "${FULL_IMAGE}" "${SCRIPT_DIR}"
docker push "${FULL_IMAGE}"

for manifest in \
  configmap.yaml \
  pv.yaml \
  pvc.yaml \
  deployment.yaml \
  service.yaml \
  ingress.yaml \
  kong-plugin-key-auth.yaml \
  kong-consumer.yaml
do
  "${kubectl_base[@]}" apply -f "${K8S_DIR}/${manifest}"
done

"${kubectl_base[@]}" -n "${NAMESPACE}" set image deployment/"${APP_NAME}" \
  "${APP_NAME}"="${FULL_IMAGE}"
"${kubectl_base[@]}" -n "${NAMESPACE}" rollout restart deployment/"${APP_NAME}"
"${kubectl_base[@]}" -n "${NAMESPACE}" rollout status deployment/"${APP_NAME}"

if [[ "${RUN_API_KEY_SETUP}" == "true" ]]; then
  KUBECTL_BIN="${KUBECTL_BIN}" \
  KUBECONFIG="${KUBECONFIG}" \
  KUBE_CONTEXT="${KUBE_CONTEXT}" \
  NAMESPACE="${NAMESPACE}" \
  K8S_DIR="${K8S_DIR}" \
  "${SCRIPT_DIR}/generate_api_key.sh"
fi

echo "Deployment completed for ${FULL_IMAGE} in namespace ${NAMESPACE}."
