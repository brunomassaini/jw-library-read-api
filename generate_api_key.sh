#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${KUBECTL_BIN:=kubectl}"
: "${KUBECONFIG:=}"
: "${KUBE_CONTEXT:=}"
: "${NAMESPACE:=default}"
: "${K8S_DIR:=${SCRIPT_DIR}/k8s}"
: "${PLUGIN_MANIFEST:=${K8S_DIR}/kong-plugin-key-auth.yaml}"
: "${CONSUMER_MANIFEST:=${K8S_DIR}/kong-consumer.yaml}"
: "${SERVICE_NAME:=jw-library-read-api}"
: "${PLUGIN_NAME:=jw-library-read-api-key-auth}"
: "${CREDENTIAL_SECRET:=jw-library-read-api-key-auth-cred}"
: "${API_KEY:=}"
: "${API_KEY_FILE:=${SCRIPT_DIR}/.apikey}"
: "${FORCE_REGENERATE:=false}"

if [[ -n "${KUBECONFIG}" ]]; then
  export KUBECONFIG
fi

if ! command -v "${KUBECTL_BIN}" >/dev/null 2>&1; then
  echo "kubectl not found: ${KUBECTL_BIN}" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate API keys." >&2
  exit 1
fi

for manifest in "${PLUGIN_MANIFEST}" "${CONSUMER_MANIFEST}"; do
  if [[ ! -f "${manifest}" ]]; then
    echo "Manifest not found: ${manifest}" >&2
    exit 1
  fi
done

kubectl_base=("${KUBECTL_BIN}")
if [[ -n "${KUBE_CONTEXT}" ]]; then
  kubectl_base+=("--context" "${KUBE_CONTEXT}")
fi

"${kubectl_base[@]}" apply -f "${PLUGIN_MANIFEST}"
"${kubectl_base[@]}" apply -f "${CONSUMER_MANIFEST}"

secret_exists=false
if "${kubectl_base[@]}" -n "${NAMESPACE}" get secret "${CREDENTIAL_SECRET}" >/dev/null 2>&1; then
  secret_exists=true
fi

if [[ "${secret_exists}" == "true" && "${FORCE_REGENERATE}" != "true" ]]; then
  echo "Secret ${CREDENTIAL_SECRET} already exists; keeping existing API key."
else
  if [[ "${secret_exists}" == "true" ]]; then
    "${kubectl_base[@]}" -n "${NAMESPACE}" delete secret "${CREDENTIAL_SECRET}"
  fi

  if [[ -z "${API_KEY}" ]]; then
    API_KEY="$(openssl rand -hex 32)"
  fi

  "${kubectl_base[@]}" -n "${NAMESPACE}" create secret generic "${CREDENTIAL_SECRET}" \
    --from-literal=key="${API_KEY}" \
    --dry-run=client -o yaml | \
    "${kubectl_base[@]}" label --local -f - konghq.com/credential=key-auth -o yaml | \
    "${kubectl_base[@]}" apply -f -

  printf "%s\n" "${API_KEY}" > "${API_KEY_FILE}"
  chmod 600 "${API_KEY_FILE}"
  echo "API key saved to ${API_KEY_FILE}"
fi

"${kubectl_base[@]}" -n "${NAMESPACE}" annotate service "${SERVICE_NAME}" \
  konghq.com/plugins="${PLUGIN_NAME}" --overwrite

echo "Kong key-auth plugin annotation applied to service ${SERVICE_NAME}."
