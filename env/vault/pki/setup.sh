#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Missing Projects"
fi

export BASE_DOMAIN=${3:-unconf.io}
export PROJECT=$1
export PKI=${PROJECT}-pki
export DOMAIN=${PROJECT}.$BASE_DOMAIN
export ROLE=${PROJECT}-$BASE_DOMAIN
export SERVICE_ACCOUNT=${PROJECT}-issuer
export WILDCARD_DOMAIN=$2

echo "Setup on ${PROJECT}"

echo "Enable PKI Engine ${PKI}"

vault secrets enable -tls-skip-verify --path=${PKI} pki
# 1 Year
vault secrets tune -tls-skip-verify -max-lease-ttl=8760h ${PKI}

vault write -tls-skip-verify ${PKI}/root/generate/internal \
    common_name=${DOMAIN} \
    ttl=8760h

echo "CRL Configuration"

vault write -tls-skip-verify ${PKI}/config/urls \
    issuing_certificates="$VAULT_ADDR/v1/${PKI}/ca" \
    crl_distribution_points="$VAULT_ADDR/v1/${PKI}/crl"

echo "$VAULT_ADDR/v1/${PKI}/ca"
echo "$VAULT_ADDR/v1/${PKI}/crl"

echo "Configure Role for domain: ${DOMAIN}"

vault write -tls-skip-verify ${PKI}/roles/${BASE_DOMAIN} \
    allowed_domains=${DOMAIN},${PROJECT}.svc,${WILDCARD_DOMAIN} \
    allow_subdomains=true \
    allowed_other_sans="*" \
    allow_glob_domains=true \
    allowed_uri_sans=*-${PROJECT}.${WILDCARD_DOMAIN} \
    max_ttl="31536000"

echo "Create PKI Policy pki-${ROLE}-policy"

vault policy write --tls-skip-verify pki-${ROLE}-policy - <<EOF
path "${PKI}*"                               { capabilities = ["read", "list"] }
path "${PKI}/roles/${BASE_DOMAIN}"   { capabilities = ["create", "update"] }
path "${PKI}/sign/${BASE_DOMAIN}"    { capabilities = ["create", "update"] }
path "${PKI}/issue/${BASE_DOMAIN}"   { capabilities = ["create"] }
EOF

echo "Authorize ServiceAccount ${SERVICE_ACCOUNT} on ${PROJECT}"

vault write --tls-skip-verify auth/kubernetes/role/${ROLE} \
  bound_service_account_names=${SERVICE_ACCOUNT} bound_service_account_namespaces="${PROJECT}" \
  policies=pki-${ROLE}-policy \
  ttl=2h
