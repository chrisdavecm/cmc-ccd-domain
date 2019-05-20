#!/bin/sh
set -e

cd "$( dirname "${BASH_SOURCE[0]}" )"

function require () {
  local command=${1}
  local installMessage=${2}
  hash ${command} 2>/dev/null || {
    logError "${command} is not installed. ${installMessage}. Aborting."
    exit 1
  }
}

function keyVaultRead() {
  az keyvault secret show --vault-name cmc-vault --name ${1} --query value -o tsv
}

if [[ ${1} = "-v" ]]; then
  export CURL_OPTS='-v'
  shift
else
  export CURL_OPTS='--fail --silent'
fi

if [ -z "${1}" ]
  then
    echo "Usage: ./upload-definition-to-env.docker.sh [env] [version]\n"
    exit 1
fi

require az "On mac run \`brew install azure-cli\`"
require python3 "On mac run \`brew install python3\`"
require jq "On mac run \`brew install jq\`"

az account show &> /dev/null || {
    echo "Please run \`az login\` and follow the instructions first"
    exit 1
}

ENV=${1}
VERSION=${2}

PROXY=http://proxyout.reform.hmcts.net:8080
IDAM_URI="http://idam-api-idam-${ENV}.service.core-compute-idam-${ENV}.internal"
AUTH_PROVIDER_BASE_URL="http://rpe-service-auth-provider-${ENV}.service.core-compute-${ENV}.internal"
CCD_STORE_BASE_URL="http://ccd-data-store-api-${ENV}.service.core-compute-${ENV}.internal"
CCD_DEF_BASE_URL="http://cmc-claim-store-${ENV}.service.core-compute-${ENV}.internal" # ccd callback url

case ${ENV} in
  local)
    PROXY=""
    IDAM_URI=http://host.docker.internal:5000
    IMPORTER_USERNAME=ccd-importer@server.net
    IMPORTER_PASSWORD=Password12
    CLIENT_SECRET=12345678
    REDIRECT_URI=http://localhost:3451/oauth2redirect
    CCD_STORE_BASE_URL=http://host.docker.internal:4451
    AUTH_PROVIDER_BASE_URL=http://host.docker.internal:4552
    CCD_DEF_BASE_URL=http://claim-store:4400 # docker-compose service
  ;;
  saat|sprod)
    IMPORTER_USERNAME=$(keyVaultRead "ccd-importer-username-test")
    IMPORTER_PASSWORD=$(keyVaultRead "ccd-importer-password-test")
    CLIENT_SECRET=$(keyVaultRead "oauth-client-secret-test")
    REDIRECT_URI=$(keyVaultRead "oauth-redirect-uri-test")
  ;;
  aat)
    IMPORTER_USERNAME=$(keyVaultRead "ccd-importer-username-preprod")
    IMPORTER_PASSWORD=$(keyVaultRead "ccd-importer-password-preprod")
    CLIENT_SECRET=$(keyVaultRead "oauth-client-secret-preprod")
    REDIRECT_URI=$(keyVaultRead "oauth-redirect-uri-preprod")
  ;;
  demo)
    IMPORTER_USERNAME=$(keyVaultRead "ccd-importer-username-demo")
    IMPORTER_PASSWORD=$(keyVaultRead "ccd-importer-password-demo")
    CLIENT_SECRET=$(keyVaultRead "oauth-client-secret-demo")
    REDIRECT_URI=$(keyVaultRead "oauth-redirect-uri-demo")
  ;;
  prod)
    IMPORTER_USERNAME=$(keyVaultRead "ccd-importer-username-prod")
    IMPORTER_PASSWORD=$(keyVaultRead "ccd-importer-password-prod")
    CLIENT_SECRET=$(keyVaultRead "oauth-client-secret-prod")
    REDIRECT_URI=$(keyVaultRead "oauth-redirect-uri-prod")
  ;;
  *)
    echo "$env not recognised"
    exit 1 ;;
esac

echo "Importing: ${VERSION}"

 # should be aligned with cmc-integration-tests docker-compose for ccd-importer
docker run \
  --name cmc-ccd-importer-to-env \
  --rm `# cleanup after` \
  -e "http_proxy=${PROXY}" \
  -e "https_proxy=${PROXY}" \
  -e "VERBOSE=${VERBOSE:-false}" \
  -e "AUTH_PROVIDER_BASE_URL=${AUTH_PROVIDER_BASE_URL}" \
  -e "MICROSERVICE=ccd_gateway" `# s2s` \
  -e "IDAM_URI=${IDAM_URI}" \
  -e "IMPORTER_USERNAME=${IMPORTER_USERNAME}" \
  -e "IMPORTER_PASSWORD=${IMPORTER_PASSWORD}" \
  -e "CLIENT_ID=ccd_gateway" \
  -e "REDIRECT_URI=${REDIRECT_URI}" \
  -e "CLIENT_SECRET=${CLIENT_SECRET}" \
  -e "CCD_STORE_BASE_URL=${CCD_STORE_BASE_URL}" \
  -e "CCD_DEF_FILENAME=cmc-ccd.xlsx" \
  -e "CCD_DEF_BASE_URL=${CCD_DEF_BASE_URL}" `# templated in definitions excel` \
  -e "USER_ROLES=citizen, caseworker-cmc, caseworker-cmc-solicitor, caseworker-cmc-systemupdate, letter-holder, caseworker-autotest1, caseworker-cmc-anonymouscitizen" \
  hmcts.azurecr.io/hmcts/cmc-ccd-definition-importer:${VERSION}

echo Finished
