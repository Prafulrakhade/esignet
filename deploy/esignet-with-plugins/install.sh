#!/bin/bash
# Installs esignet helm chart
## Usage: ./install.sh [kubeconfig]

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet
ESIGNET_SERVICE_NAME=esignet
CHART_VERSION=2.0.0-develop
echo Create $NS namespace
kubectl create ns $NS

function installing_esignet() {

  while true; do
      read -p "Do you want to continue installing esignet services? (y/n): " ans
      if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
          break
      elif [ "$ans" = "N" ] || [ "$ans" = "n" ]; then
          exit 1
      else
          echo "Please provide a correct option (Y or N)"
      fi
  done

  echo Istio label
  kubectl label ns $NS istio-injection=enabled --overwrite
  helm repo add mosip https://mosip.github.io/mosip-helm
  helm repo update

  COPY_UTIL=../copy_cm_func.sh
  $COPY_UTIL configmap postgres-config postgres $NS
  $COPY_UTIL configmap redis-config redis $NS
  $COPY_UTIL secret redis redis $NS

  while true; do
    read -p "Is Prometheus Service Monitor Operator deployed in the k8s cluster? (y/n): " response
    if [[ "$response" == "y" || "$response" == "Y" ]]; then
      servicemonitorflag=true
      break
    elif [[ "$response" == "n" || "$response" == "N" ]]; then
      servicemonitorflag=false
      break
    else
      echo "Not a correct response. Please respond with y (yes) or n (no)."
    fi
  done

  echo "Do you have public domain & valid SSL? (Y/n) "
  echo "Y: if you have public domain & valid ssl certificate"
  echo "n: If you don't have a public domain and a valid SSL certificate. Note: It is recommended to use this option only in development environments."
  read -p "" flag

  if [ -z "$flag" ]; then
    echo "'flag' was not provided; EXITING;"
    exit 1;
  fi

  ENABLE_INSECURE=''
  if [ "$flag" = "n" ]; then
    ENABLE_INSECURE='--set enable_insecure=true';
  fi

  ESIGNET_HELM_ARGS=''
  keystore_env_vars=""
  extra_env_vars_additional=""
  plugin_option=""
  plugin_name=""

  # ---------------------------------------------------------------------
  # Plugin selection. The keystore type is now derived from this choice:
  #   mock    -> PKCS12
  #   mosip   -> PKCS11
  #   sunbird -> PKCS11
  # ---------------------------------------------------------------------
  echo "Please choose the required plugin to proceed with installation"
  echo "1. mock"
  echo "2. mosip"
  echo "3. sunbird"
  read -p "Enter the plugin number: " plugin_no
  echo "$plugin_no" > /tmp/plugin_no.txt

  while true; do
    if [[ "$plugin_no" == "1" ]]; then
      plugin_name="mock"
      read -p "Is the mock plugin deployed in the default namespace? (y/n): " mock_default_ns
      if [[ "$mock_default_ns" =~ ^[Yy]$ ]]; then
            mock_domain_url="http://mock-identity-system.mockid"
          else
            read -p "Enter MOSIP_ESIGNET_MOCK_DOMAIN_URL: " mock_domain_url

            if [[ -z "$mock_domain_url" ]]; then
              echo "ERROR: MOSIP_ESIGNET_MOCK_DOMAIN_URL cannot be empty."
              continue
            fi
          fi
          extra_env_vars_additional+="  \"MOSIP_ESIGNET_MOCK_DOMAIN_URL\": \"$mock_domain_url\""$'\n'
          break
      break

    elif [[ "$plugin_no" == "2" ]]; then
      echo "Setting up dummy values for Esignet MISP license key"
      kubectl -n $NS create secret generic esignet-misp-onboarder-key --from-literal=mosip-esignet-misp-key='' --dry-run=client -o yaml | kubectl apply -f -
      plugin_name="mosip"
      declare -A urls=(
        ["MOSIP_ESIGNET_AUTHENTICATOR_IDA_CERT_URL"]="http://mosip-file-server.mosip-file-server/mosip-certs/ida-partner.cer"
        ["MOSIP_ESIGNET_AUTHENTICATOR_IDA_KYC-AUTH-URL"]="http://ida-auth.ida/idauthentication/v1/kyc-auth/delegated/\${mosip.esignet.authenticator.ida.misp-license-key}/"
        ["MOSIP_ESIGNET_AUTHENTICATOR_IDA_KYC-EXCHANGE-URL"]="http://ida-auth.ida/idauthentication/v1/kyc-exchange/delegated/\${mosip.esignet.authenticator.ida.misp-license-key}/"
        ["MOSIP_ESIGNET_AUTHENTICATOR_IDA_SEND-OTP-URL"]="http://ida-otp.ida/idauthentication/v1/otp/\${mosip.esignet.authenticator.ida.misp-license-key}/"
        ["MOSIP_ESIGNET_BINDER_IDA_KEY-BINDING-URL"]="http://ida-auth.ida/idauthentication/v1/identity-key-binding/delegated/\${mosip.esignet.authenticator.ida.misp-license-key}/"
        ["MOSIP_ESIGNET_AUTHENTICATOR_IDA_GET-CERTIFICATES-URL"]="http://ida-internal.ida/idauthentication/v1/internal/getAllCertificates"
        ["MOSIP_ESIGNET_AUTHENTICATOR_IDA_AUTH-TOKEN-URL"]="http://authmanager.kernel/v1/authmanager/authenticate/clientidsecretkey"
        ["MOSIP_ESIGNET_AUTHENTICATOR_IDA_AUDIT-MANAGER-URL"]="http://auditmanager.kernel/v1/auditmanager/audits"
        ["MOSIP_ESIGNET_AUTHENTICATOR_IDA_OTP-CHANNELS"]="email,phone"
      )

      ordered_keys=(
        "MOSIP_ESIGNET_AUTHENTICATOR_IDA_CERT_URL"
        "MOSIP_ESIGNET_AUTHENTICATOR_IDA_KYC-AUTH-URL"
        "MOSIP_ESIGNET_AUTHENTICATOR_IDA_KYC-EXCHANGE-URL"
        "MOSIP_ESIGNET_AUTHENTICATOR_IDA_SEND-OTP-URL"
        "MOSIP_ESIGNET_BINDER_IDA_KEY-BINDING-URL"
        "MOSIP_ESIGNET_AUTHENTICATOR_IDA_GET-CERTIFICATES-URL"
        "MOSIP_ESIGNET_AUTHENTICATOR_IDA_AUTH-TOKEN-URL"
        "MOSIP_ESIGNET_AUTHENTICATOR_IDA_AUDIT-MANAGER-URL"
        "MOSIP_ESIGNET_AUTHENTICATOR_IDA_OTP-CHANNELS"
      )

      for key in "${ordered_keys[@]}"; do
        if [[ "$key" == "MOSIP_ESIGNET_AUTHENTICATOR_IDA_OTP-CHANNELS" ]]; then
          read -p "Default channels (${urls[$key]})  Please add required channels to override the default channels: " user_input
        else
          read -p "Default (${urls[$key]}) - Provide custom value (if applicable) to override the default url: " user_input
        fi
        value="${user_input:-${urls[$key]}}"
        extra_env_vars_additional+="  \"$key\": \"$value\""$'\n'
      done
      # MOSIP_LICENSE_KEY references the existing esignet-misp-onboarder-key secret
      extra_env_vars_additional+="  MOSIP_ESIGNET_MISP_KEY:"$'\n'
      extra_env_vars_additional+="    valueFrom:"$'\n'
      extra_env_vars_additional+="      secretKeyRef:"$'\n'
      extra_env_vars_additional+="        name: esignet-misp-onboarder-key"$'\n'
      extra_env_vars_additional+="        key: mosip-esignet-misp-key"$'\n'
      break

    elif [[ "$plugin_no" == "3" ]]; then
      plugin_name="sunbird"
      read -p "Provide the URL for Sunbird registry: " sunbird_registry_url
      extra_env_vars_additional+="  \"MOSIP_ESIGNET_AUTHENTICATOR_SUNBIRD_RC_REGISTRY_GET_URL\": \"$sunbird_registry_url\""$'\n'
      extra_env_vars_additional+="  \"MOSIP_ESIGNET_AUTHENTICATOR_SUNBIRD_RC_AUTH_FACTOR_KBI_REGISTRY_SEARCH_URL\": \"$sunbird_registry_url/api/v1/Insurance/search\""$'\n'
      extra_env_vars_additional+="  \"MOSIP_ESIGNET_AUTHENTICATOR_DEFAULT_AUTH_FACTOR_KBI_INDIVIDUAL_ID_FIELD\": \"\${mosip.esignet.authenticator.sunbird-rc.auth-factor.kbi.individual-id-field}\""$'\n'
      extra_env_vars_additional+="  \"MOSIP_ESIGNET_AUTHENTICATOR_DEFAULT_AUTH_FACTOR_KBI_FIELD_DETAILS\": \"\${mosip.esignet.authenticator.sunbird-rc.auth-factor.kbi.field-details}\""$'\n'
      break
    else
      echo "Please provide the correct plugin number (1, 2, or 3)."
      read -p "Enter the plugin number: " plugin_no
    fi
  done

  # ---------------------------------------------------------------------
  # Keystore configuration, determined by the selected plugin:
  #   mock               -> PKCS12
  #   mosip / sunbird     -> PKCS11
  # ---------------------------------------------------------------------
  if [[ "$plugin_name" == "mock" ]]; then
    echo "Plugin 'mock' selected - configuring PKCS12 keystore."

    # ---------------- PKCS12 flow ----------------
    default_volume_size=100M
    read -p "Provide the size for volume [ default : 100M ]: " volume_size
    volume_size=${volume_size:-$default_volume_size}

    default_volume_mount_path='/home/mosip/config/'
    read -p "Provide the mount path for volume [ default : '/home/mosip/config/' ] : " volume_mount_path
    volume_mount_path=${volume_mount_path:-$default_volume_mount_path}

    PVC_CLAIM_NAME='esignet-pkcs12'
    ESIGNET_HELM_ARGS="--set persistence.enabled=true  \
                       --set volumePermissions.enabled=true \
                       --set persistence.size=$volume_size \
                       --set persistence.mountDir=\"$volume_mount_path\" \
                       --set persistence.pvc_claim_name=\"$PVC_CLAIM_NAME\"  \
                      "

    keystore_env_vars+="  KEYMANAGER_KEYSTORE_TYPE: \"PKCS12\""$'\n'

    default_pkcs12_file_path="/opt/mosip/test.pfx"
    read -p "Provide KEYMANAGER_PKCS12_FILE_PATH [default: $default_pkcs12_file_path]: " pkcs12_file_path
    pkcs12_file_path=${pkcs12_file_path:-$default_pkcs12_file_path}

    # Generate a random KEYMANAGER_PKCS12_PASSWORD and store it as a Kubernetes
    # Secret in the same namespace, matching the chart's documented convention
    # (secretKeyRef: esignet-keymanager / pkcs12-password) instead of a plain value.
    pkcs12_password=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | cut -c1-16)
    kubectl -n "$NS" create secret generic esignet-keymanager \
      --from-literal=pkcs12-password="$pkcs12_password" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "Generated KEYMANAGER_PKCS12_PASSWORD and stored it in secret 'esignet-keymanager' (key: pkcs12-password) in namespace '$NS'."

    keystore_env_vars+="  KEYMANAGER_PKCS12_FILE_PATH: \"$pkcs12_file_path\""$'\n'
    keystore_env_vars+="  KEYMANAGER_PKCS12_PASSWORD:"$'\n'
    keystore_env_vars+="    valueFrom:"$'\n'
    keystore_env_vars+="      secretKeyRef:"$'\n'
    keystore_env_vars+="        name: esignet-keymanager"$'\n'
    keystore_env_vars+="        key: pkcs12-password"$'\n'

  else
    echo "Plugin '$plugin_name' selected - configuring PKCS11 keystore."

    # ---------------- PKCS11 flow ----------------
    # NOTE: KEYMANAGER_PKCS11_PIN is intentionally NOT prompted for here.
    # values.yaml already defaults it to a secretKeyRef (esignet-softhsm/security-pin),
    # and that secret is created as part of the softhsm/PKCS11 install flow below.
    # Overriding it with a plain-text value here would replace a working secret
    # reference with a literal, so we leave the chart default untouched.

    default_pkcs11_module_path="/usr/local/lib/softhsm/libpkcs11-proxy.so"
    default_pkcs11_token_label="mosip-token"
    default_hsm_client_zip_url_env="https://raw.githubusercontent.com/mosip/mosip-infra/master/deployment/v3/external/hsm/hsm-client.zip"

    echo "The default esignet deployment already configures PKCS11 with:"
    echo "  KEYMANAGER_PKCS11_MODULE_PATH = $default_pkcs11_module_path"
    echo "  KEYMANAGER_PKCS11_TOKEN_LABEL = $default_pkcs11_token_label"
    echo "  hsm_client_zip_url_env        = $default_hsm_client_zip_url_env"

    while true; do
      read -p "Do you want to proceed with these default values? (y/n): " use_pkcs11_defaults
      if [[ "$use_pkcs11_defaults" == "y" || "$use_pkcs11_defaults" == "Y" ]]; then
        pkcs11_module_path="$default_pkcs11_module_path"
        pkcs11_token_label="$default_pkcs11_token_label"
        hsm_client_zip_url_env="$default_hsm_client_zip_url_env"
        break
      elif [[ "$use_pkcs11_defaults" == "n" || "$use_pkcs11_defaults" == "N" ]]; then
        read -p "Provide KEYMANAGER_PKCS11_MODULE_PATH [default: $default_pkcs11_module_path]: " pkcs11_module_path
        pkcs11_module_path=${pkcs11_module_path:-$default_pkcs11_module_path}

        read -p "Provide KEYMANAGER_PKCS11_TOKEN_LABEL [default: $default_pkcs11_token_label]: " pkcs11_token_label
        pkcs11_token_label=${pkcs11_token_label:-$default_pkcs11_token_label}

        read -p "Provide hsm_client_zip_url_env [default: $default_hsm_client_zip_url_env]: " hsm_client_zip_url_env
        hsm_client_zip_url_env=${hsm_client_zip_url_env:-$default_hsm_client_zip_url_env}
        break
      else
        echo "Please provide a correct option (y or n)."
      fi
    done

    keystore_env_vars+="  KEYMANAGER_KEYSTORE_TYPE: \"PKCS11\""$'\n'
    keystore_env_vars+="  KEYMANAGER_PKCS11_MODULE_PATH: \"$pkcs11_module_path\""$'\n'
    keystore_env_vars+="  KEYMANAGER_PKCS11_TOKEN_LABEL: \"$pkcs11_token_label\""$'\n'

    # Run the existing PKCS11 installation script/flow.
    # hsm_client_zip_url_env is not a chart env var (it doesn't appear in values.yaml),
    # so it's exported only for the install script to consume, not written to the Helm overlay.
    # Set PKCS11_INSTALL_SCRIPT env var before running this script to override the path.
    PKCS11_INSTALL_SCRIPT=${PKCS11_INSTALL_SCRIPT:-../pkcs11-install.sh}
    if [ -x "$PKCS11_INSTALL_SCRIPT" ]; then
      echo "Running PKCS11 installation script: $PKCS11_INSTALL_SCRIPT"
      hsm_client_zip_url_env="$hsm_client_zip_url_env" "$PKCS11_INSTALL_SCRIPT"
    else
      echo "WARNING: PKCS11 installation script not found or not executable at '$PKCS11_INSTALL_SCRIPT'."
      echo "Please ensure PKCS11 is installed/configured on the target nodes before proceeding, or set PKCS11_INSTALL_SCRIPT to the correct path."
    fi

    # ---------------- KEYMANAGER_PKCS11_PIN (optional override) ----------------
    # The chart's default extraEnvVars already reference this via secretKeyRef
    # (esignet-softhsm/security-pin), so instead of writing a literal into the
    # Helm overlay, we just update that key on the existing secret if the user
    # supplies a value. If they don't, the default pin already set by the
    # softhsm/PKCS11 install flow above is left as-is.
    while true; do
      read -p "Do you want to provide a custom value for KEYMANAGER_PKCS11_PIN? (y/n): " override_pin
      if [[ "$override_pin" == "y" || "$override_pin" == "Y" ]]; then
        read -s -p "Enter the new value for KEYMANAGER_PKCS11_PIN: " pkcs11_pin
        echo
        if [[ -z "$pkcs11_pin" ]]; then
          echo "No value entered; keeping the existing default PIN."
        else
          kubectl -n $NS patch secret esignet-softhsm --type='json' \
            -p="[{\"op\":\"replace\",\"path\":\"/data/security-pin\",\"value\":\"$(printf '%s' "$pkcs11_pin" | base64 | tr -d '\n')\"}]"
          echo "Updated the 'security-pin' key in the existing 'esignet-softhsm' secret."
        fi
        break
      elif [[ "$override_pin" == "n" || "$override_pin" == "N" ]]; then
        echo "Keeping the default KEYMANAGER_PKCS11_PIN from the existing 'esignet-softhsm' secret."
        break
      else
        echo "Please provide a correct option (y or n)."
      fi
    done
  fi

  # ---------------------------------------------------------------------
  # MOSIP_ESIGNET_AUTHN_PROVIDER is derived from the plugin selected above
  # (mock -> mock, mosip -> mosip, sunbird -> sunbird).
  # NAMESPACE holds the actual k8s namespace the chart is deployed into.
  # ---------------------------------------------------------------------
  extra_env_vars_additional+="  \"MOSIP_ESIGNET_AUTHN_PROVIDER\": \"$plugin_name\""$'\n'
  extra_env_vars_additional+="  \"NAMESPACE\": \"$NS\""$'\n'

  if kubectl get secret esignet-captcha -n "$NS" &>/dev/null; then
    extra_env_vars_additional+="  MOSIP_ESIGNET_CAPTCHA_SITE_KEY:"$'\n'
    extra_env_vars_additional+="    valueFrom:"$'\n'
    extra_env_vars_additional+="      secretKeyRef:"$'\n'
    extra_env_vars_additional+="        name: esignet-captcha"$'\n'
    extra_env_vars_additional+="        key: esignet-captcha-site-key"$'\n'
  else
    extra_env_vars_additional+="  \"MOSIP_ESIGNET_CAPTCHA_SITE_KEY\": \"\""$'\n'
  fi

  # Combine keystore (pkcs12/pkcs11) env vars and plugin-specific env vars
  plugin_env_file=$(mktemp)
  combined_env_vars="${keystore_env_vars}${extra_env_vars_additional}"
  if [[ -n "$combined_env_vars" ]]; then
    cat <<EOF > "$plugin_env_file"
extraEnvVarsAdditional:
$combined_env_vars
EOF
  fi

  plugin_option="--set pluginNameEnv=$plugin_name -f $plugin_env_file"

  echo Installing esignet
  helm -n $NS install $ESIGNET_SERVICE_NAME /home/techno-467/IdeaProjects/esignet/helm/esignet --version $CHART_VERSION  \
    $ENABLE_INSECURE $plugin_option \
    $ESIGNET_HELM_ARGS \
    --set extraEnvVarsCM={esignet-softhsm-share} \
    --set metrics.serviceMonitor.enabled=$servicemonitorflag -f values.yaml --wait

  kubectl -n $NS get deploy $ESIGNET_SERVICE_NAME -o name | xargs -n1 -t kubectl -n $NS rollout status

  echo Installed esignet service
  return 0
}

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes
installing_esignet   # calling function