#!/usr/bin/env bash
# Lets machines require our signature: adds our registry to the container policy.
# It only takes effect after `bootc switch --enforce-container-sigpolicy`, see README.
set -euxo pipefail

KEY=/usr/share/bootc-images/cosign.pub
test -s "$KEY"

policy=$(mktemp)
jq --arg key "$KEY" '.transports.docker["ghcr.io/ysantalla"] = [{
    type: "sigstoreSigned",
    keyPath: $key,
    signedIdentity: {type: "matchRepository"}
  }]' /etc/containers/policy.json > "$policy"
install -m 0644 "$policy" /etc/containers/policy.json
rm -f "$policy"

cat > /etc/containers/registries.d/bootc-images.yaml <<'YAML'
docker:
  ghcr.io/ysantalla:
    use-sigstore-attachments: true
YAML
