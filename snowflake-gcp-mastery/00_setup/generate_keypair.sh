#!/usr/bin/env bash
# Generate an encrypted RSA key pair for Snowflake key-pair authentication.
#
# Run in Git Bash (Windows) or any Linux/macOS shell:
#   bash 00_setup/generate_keypair.sh desmond
#   bash 00_setup/generate_keypair.sh svc_retail_pipeline
#
# Output (outside the repo, so it can never be committed):
#   ~/.snowflake/keys/<name>_rsa_key.p8   private key (encrypted, PKCS#8)  -> stays on this machine
#   ~/.snowflake/keys/<name>_rsa_key.pub  public key                       -> goes into Snowflake
set -euo pipefail

NAME="${1:?usage: generate_keypair.sh <name>   e.g. desmond or svc_retail_pipeline}"
KEY_DIR="${HOME}/.snowflake/keys"
PRIV="${KEY_DIR}/${NAME}_rsa_key.p8"
PUB="${KEY_DIR}/${NAME}_rsa_key.pub"

mkdir -p "${KEY_DIR}"

if [[ -f "${PRIV}" ]]; then
  echo "Key already exists: ${PRIV}"
  echo "Delete it first if you really want a new one (and update Snowflake afterwards)."
  exit 1
fi

echo ">> Creating encrypted private key. You will be asked for a passphrase twice."
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes256 -inform PEM -out "${PRIV}"

echo ">> Deriving public key (enter the same passphrase)."
openssl rsa -in "${PRIV}" -pubout -out "${PUB}"

chmod 600 "${PRIV}" || true

# Body of the public key without header/footer/newlines: this is what Snowflake wants.
PUB_BODY="$(grep -v -- '-----' "${PUB}" | tr -d '\n\r')"
FINGERPRINT="SHA256:$(openssl rsa -pubin -in "${PUB}" -outform DER 2>/dev/null | openssl dgst -sha256 -binary | openssl enc -base64)"

USER_UPPER="$(echo "${NAME}" | tr '[:lower:]' '[:upper:]')"

cat <<EOF

Done.
  Private key : ${PRIV}
  Public key  : ${PUB}
  Fingerprint : ${FINGERPRINT}

Run this in Snowflake (Snowsight worksheet) to register the public key:

  USE ROLE SECURITYADMIN;
  ALTER USER ${USER_UPPER} SET RSA_PUBLIC_KEY = '${PUB_BODY}';
  DESC USER ${USER_UPPER};   -- RSA_PUBLIC_KEY_FP should equal ${FINGERPRINT}

(If your Snowflake login name is different from '${USER_UPPER}', change it in the statement.)
EOF
