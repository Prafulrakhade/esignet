#!/bin/bash
# Installs HSM service for Esignet (SoftHSM or Hardware HSM)
## Usage: ./install.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

SOFTHSM_NS=esignet
SOFTHSM_CHART_VERSION=12.0.1

function installing_softhsm() {
  echo "Create $SOFTHSM_NS namespaces"
  kubectl create ns $SOFTHSM_NS || true

  echo "Istio label"
  kubectl label ns $SOFTHSM_NS istio-injection=enabled --overwrite
  helm repo update

  # Deploy Softhsm for Esignet.
  echo "Installing Softhsm for esignet"
  helm -n "$SOFTHSM_NS" install esignet-softhsm mosip/softhsm -f softhsm-values.yaml --version "$SOFTHSM_CHART_VERSION" --wait
  echo "Installed Softhsm for esignet"

  return 0
}

function prompt_hsm_choice() {
  echo ""
  echo "Which HSM deployment do you want to use?"
  echo "  1) SoftHSM (software-based, installed via Helm)"
  echo "  2) Hardware HSM"
  echo ""
  read -rp "Enter your choice [1-2]: " HSM_CHOICE

  case "$HSM_CHOICE" in
    1)
      installing_softhsm
      ;;
    2)
      echo ""
      echo "Hardware HSM setup is not available yet. Please check back later or contact the platform team for assistance."
      echo "Exiting without making any changes."
      exit 0
      ;;
    *)
      echo "Invalid choice: '$HSM_CHOICE'. Please enter 1 or 2."
      prompt_hsm_choice
      ;;
  esac
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes

prompt_hsm_choice   # ask user for HSM type and act accordingly