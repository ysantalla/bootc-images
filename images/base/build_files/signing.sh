#!/usr/bin/env bash
# Requires our signature for every image from our registry: adds it, with our key, to the
# container policy. The policy's default is to reject, so a machine running this image
# checks that signature on every pull, with or without --enforce-container-sigpolicy.
set -euxo pipefail

KEY=/usr/share/katze/cosign.pub
test -s "$KEY"

policy=$(mktemp)
jq --arg key "$KEY" '.transports.docker["ghcr.io/ysantalla"] = [{
    type: "sigstoreSigned",
    keyPath: $key,
    signedIdentity: {type: "matchRepository"}
  }]' /etc/containers/policy.json > "$policy"
install -m 0644 "$policy" /etc/containers/policy.json
rm -f "$policy"

cat > /etc/containers/registries.d/katze.yaml <<'YAML'
docker:
  ghcr.io/ysantalla:
    use-sigstore-attachments: true
YAML
