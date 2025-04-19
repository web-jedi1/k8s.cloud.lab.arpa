# Vault Agent-Based Certificate Management for Kubernetes Control Plane
<br>

## Overview
This architecture securely provisions, issues, and rotates Kubernetes control plane certificates using:

- **HashiCorp Vault** for PKI and secret lifecycle
- **Vault Agent** running on each control plane node
- **Ansible** for initial bootstrap and token provisioning
<br>

### Workflow Summary
1. **Ansible** uses `cert` authentication to:
   - Lookup or create a Vault **Entity** per control plane node
   - Issue a **bootstrap token** tied to that entity
   - Write token to `/etc/vault.d/bootstrap-token`

2. **Vault Agent** on each node:
   - Uses the bootstrap token with `auto_auth`
   - Retrieves a Vault session token (`vault-token`)
   - Renders all required certs via `template` blocks
   - Executes post-render `command` (e.g. reload kube-apiserver)
<br>

### Token Scope & Policy
- **Bootstrap Token**
  - Short TTL (e.g. `12h`)
  - Policies:
    - `vault-agent-policy`
    - `k8s-issuing-control-plane`
  - Scoped to Vault entity (`vault-agent-<hostname>`)

- **vault-agent-policy**
  - Allows token renewal, self-lookup, reissue
  - Can optionally access ingress cert issuance

- **k8s-issuing-control-plane**
  - Grants access to Vault PKI roles:
    - `apiserver`
    - `apiserver-kubelet-client`
    - `front-proxy-client`
<br>

### Certificate Templates (Rendered by Vault Agent)
| Cert/Key File                              | Vault PKI Role                | Notes                         |
|--------------------------------------------|-------------------------------|-------------------------------|
| `/etc/kubernetes/pki/apiserver.crt/key`    | `apiserver`                   | Cluster API TLS endpoint      |
| `/etc/kubernetes/pki/apiserver-kubelet-client.crt/key` | `apiserver-kubelet-client` | Per-node identity for Kubelet auth |
| `/etc/kubernetes/pki/front-proxy-client.crt/key`       | `front-proxy-client`        | For aggregated API requests   |
| `/etc/kubernetes/pki/ca.crt`               | Static or templated           | Shared root CA                |
| `/etc/kubernetes/pki/sa.key/pub`           | Static or templated           | Shared signing keys           |
<br>

### Security Architecture
| Component        | Role                                  |
|------------------|----------------------------------------|
| Ansible Host     | High-trust bootstrap w/ cert auth      |
| Vault Agent      | Low-trust runtime, least-privilege     |
| Vault Entity     | Binds token to a specific node identity|
| PKI Roles        | Enforce SANs, TTLs, and EKUs           |
<br>

### Benefits
- Fully automated cert provisioning and renewal
- No static keys or manual CA handling
- Least privilege across bootstrap/runtime
- Per-node traceability via Vault entities
- Can be extended to manage etcd or ingress certs
<br>

### Optional Extensions
- Add ingress cert issuance via AD-trusted intermediate
- Extend roles to handle etcd peer certs
- Use dynamic secret rendering for kubeconfigs
- Alerting on cert expiry via Vault or monitoring stack
<br>

## Setup Ansible Role
```bash
cat << EOF > ansible-bootstrap-policy.hcl
# Allow creation of identity entities (for Vault Agent)
path "identity/entity" {
  capabilities = ["create", "update"]
}

# Allow reading/updating specific named entities (e.g. "vault-agent-<hostname>")
path "identity/entity/name/*" {
  capabilities = ["read", "update"]
}

# Allow reading/updating entity by ID (returned after creation)
path "identity/entity/id/*" {
  capabilities = ["read", "update"]
}

# Allow creation of entity aliases (e.g. for cert/k8s auth)
path "identity/entity-alias" {
  capabilities = ["create", "update"]
}

# Allow reading aliases by ID (linked to entities)
path "identity/entity-alias/id/*" {
  capabilities = ["read", "update"]
}

# Allow bootstrapping Vault Agent tokens (with strict controls)
path "auth/token/create" {
  capabilities = ["create", "update"]
  allowed_parameters = {
    "policies" = ["vault-agent-policy", "k8s-issuing-control-plane"]
    "ttl" = ["12h"]
    "explicit_max_ttl" = ["24h"]
    "renewable" = ["true"]
    "orphan" = ["true"]
    "entity_id" = ["*"]
    "metadata" = ["*"]
    "no_default_policy" = ["true"]
  }
}

# Optional: allow Ansible to inspect the token it just created (or itself)
path "auth/token/lookup" {
  capabilities = ["read"]
}

EOF
vault policy write ansible-bootstrap-policy ansible-bootstrap-policy.hcl
```
<br>

## Setup Issuers
```bash
vault_url=""
while true; do
  read -p "Input Vault URL (e.g. https://vault.lab.local:8220): " vault_url
  if [[ $vault_url =~ ^https://[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
    break
  else
    echo "Invalid format. Please use format: https://hostname:port"
  fi
done

if ! vault secrets list | grep -q "pki_k8s/"; then
  echo "Enabling pki_k8s at /pki_k8s..."
  vault secrets enable -path=pki_k8s pki
  vault secrets tune -max-lease-ttl=87600h pki_k8s
else
  echo "pki_k8s already exists, skipping enable."
fi

if ! vault read pki_k8s/cert/ca > /dev/null 2>&1; then
  echo "Creating root CA for pki_k8s..."
  vault write pki_k8s/root/generate/internal \
    common_name="K8S Root CA" \
    ttl=87600h

else
  echo "Root CA already exists in pki_k8s, skipping creation."
fi

vault write pki_k8s/config/urls \
    issuing_certificates="$vault_url/v1/pki_k8s/ca" \
    crl_distribution_points="$vault_url/v1/pki_k8s/crl"

if ! vault secrets list | grep -q "pki_k8s_issuing/"; then
  echo "Enabling pki_k8s_issuing at /pki_k8s_issuing..."
  vault secrets enable -path=pki_k8s_issuing pki
  vault secrets tune -max-lease-ttl=43800h pki_k8s_issuing
else
  echo "pki_k8s_issuing already exists, skipping enable."
fi

vault write pki_k8s_issuing/config/urls \
    issuing_certificates="$vault_url/v1/pki_k8s_issuing/ca" \
    crl_distribution_points="$vault_url/v1/pki_k8s_issuing/crl"

if ! vault read pki_k8s_issuing/cert/ca > /dev/null 2>&1; then
  echo "Creating intermediate CSR in pki_k8s_issuing..."
  vault write -format=json pki_k8s_issuing/intermediate/generate/internal \
    common_name="K8S Intermediate CA" \
    | jq -r '.data.csr' > k8s-intermediate.csr
else
  echo "Intermediate CA already initialized in pki_k8s_issuing, skipping CSR generation."
fi

if [ -f "k8s-intermediate.csr" ]; then
  echo "Signing intermediate CSR with root CA..."
  vault write -format=json pki_k8s/root/sign-intermediate \
    csr=@k8s-intermediate.csr \
    format=pem_bundle \
    ttl=43800h \
    | jq -r '.data.certificate' > k8s-intermediate-cert.pem

  echo "Setting signed cert into pki_k8s_issuing..."
  vault write pki_k8s_issuing/intermediate/set-signed \
    certificate=@k8s-intermediate-cert.pem
else
  echo "Intermediate cert already set, skipping signing."
fi

echo "PKI setup complete for root (pki_k8s) and intermediate (pki_k8s_issuing)."
```
<br>

## Setup Roles for k8s control plane
```bash
# apiserver
vault write pki_k8s_issuing/roles/apiserver \
  allowed_domains="cluster.local" \
  allow_subdomains=true \
  allow_bare_domains=true \
  enforce_hostnames=false \
  server_flag=true \
  client_flag=false \
  max_ttl="72h"

# apiserver-kubelet-client (per node)
vault write pki_k8s_issuing/roles/apiserver-kubelet-client \
  allowed_domains="{{ your_domain }}" \
  allow_bare_domains=true \
  allow_subdomains=true \
  enforce_hostnames=true \
  allow_glob_domains=true \
  server_flag=false \
  client_flag=true \
  max_ttl="72h"

# front-proxy-client (per node)
vault write pki_k8s_issuing/roles/front-proxy-client \
  allowed_domains="{{ your_domain }}" \
  allow_bare_domains=true \
  allow_subdomains=true \
  enforce_hostnames=true \
  allow_glob_domains=true \
  server_flag=true \
  client_flag=true \
  max_ttl="72h"
```
<br>

## Create vault-agent-policy.hcl
```bash
cat << EOF > vault-agent-policy.hcl
# Allow Vault Agent to request control plane certificates
path "pki_k8s_issuing/issue/*" {
  capabilities = ["read", "update"]
}

# Allow reading CA cert (if needed for validation)
path "pki_k8s_issuing/ca" {
  capabilities = ["read"]
}

# Allow Vault Agent to re-issue its own token
path "auth/token/create" {
  capabilities = ["create", "update"]
  allowed_parameters = {
    "policies" = ["vault-agent-policy", "k8s-issuing-control-plane"]
    "entity_id" = ["*"]
    "ttl" = ["12h"]
    "explicit_max_ttl" = ["12h"]
    "renewable" = ["true"]
    "orphan" = ["true"]
    "metadata" = ["*"]
  }
}

# Allow Vault Agent to renew itself
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow reading its own identity
path "identity/entity/id/*" {
  capabilities = ["read"]
}

# Allow read and issue kubernetes ingress certificates
path "pki/issue/k8s-ingress" {
  capabilities = ["read", "update"]
}
EOF
vault policy write vault-agent-policy vault-agent-policy.hcl
```
<br>

## Create k8s-issuing-control-plane policy
```bash
cat << EOF > k8s-issuing-control-plane.hcl
path "pki_k8s_issuing/issue/apiserver" {
  capabilities = ["read", "update"]
}

path "pki_k8s_issuing/issue/apiserver-kubelet-client" {
  capabilities = ["read", "update"]
}

path "pki_k8s_issuing/issue/front-proxy-client" {
  capabilities = ["read", "update"]
}
EOF
vault policy write k8s-issuing-control-plane k8s-issuing-control-plane.hcl
```
<br>

## Restrict VaultAgent auth-auth Token Usage
```bash
vault write auth/token/roles/k8s-bootstrap-tokens \
  allowed_policies="vault-agent-policy,k8s-issuing-control-plane" \
  default_policies="vault-agent-policy,k8s-issuing-control-plane" \
  orphan=true \
  renewable=true \
  period="12h" \
  explicit_max_ttl="24h"
```
<br>

## Bonus: k8s-ingress certificates
In cases where a trusted certificate for kubernetes ingress is needed,
this can be provisioned as follows:
<br>

0. Add mount point
```bash
read -p "Enter your Hashi Vault PKI Mount Point: " pki_mount_point
```
1. Add ability of vault-agent-policy to issue certs from this mount point
```bash
POLICY_NAME="vault-agent-policy"
NEW_PATH_BLOCK=$(cat <<EOF
path "$pki_mount_point/issue/k8s-ingress" {
  capabilities = ["read", "update"]
}
EOF
)
vault policy read "$POLICY_NAME" > tmp_policy.hcl && \
echo "$NEW_PATH_BLOCK" >> tmp_policy.hcl && \
vault policy write "$POLICY_NAME" tmp_policy.hcl && \
rm tmp_policy.hcl
```
<br>

### Internal Intermediate CA (Active Directory for example)
The flow is easy in this setup. vault-agent on the host can just ask the Intermediate CA mounted at "pki" to issue a new certificate, thereby always keeping the ingress certificate up to date and including all required auditability with vault.
1. Create PKI Role
```bash
read -p "Enter your AD Domain Name here: " domain_name
if [[ "$domain_name" =~ ^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$ ]]; then
  vault write pki/roles/k8s-ingress \
    allowed_domains="$domain_name" \
    allow_subdomains=true \
    allow_bare_domains=false \
    allow_localhost=false \
    client_flag=false \
    server_flag=true \
    key_type="ec" \
    key_bits=256 \
    max_ttl="72h"
else
  echo "[!] -> Invalid domain name format. Please enter a valid FQDN (e.g., arpa.local)."
fi
```
<br>

2. Add this to k8s-issuing-control-plane role
```bash
POLICY_NAME="k8s-issuing-control-plane"
read -p "Enter your Hashi Vault PKI Mount Point: " pki_mount_point
NEW_PATH_BLOCK=$(cat <<EOF
path "$PKI_MOUNT_POINT/issue/k8s-ingress" {
  capabilities = ["read", "update"]
}
EOF
)

# Read, append, write, and clean up
vault policy read "$POLICY_NAME" > tmp_policy.hcl && \
echo "$NEW_PATH_BLOCK" >> tmp_policy.hcl && \
vault policy write "$POLICY_NAME" tmp_policy.hcl && \
rm tmp_policy.hcl
```
<br>

### Lets Encrypt ACME
Here the workflow is more complicated, as vault cannot proxy for Lets Encrypt ACME.
1. Certbot renews your public cert (Let's Encrypt)
2. Cert + key are uploaded into Vault (KV or PKI-less storage)
3. Vault Agent renders cert+key via template
4. Ingress sees the new cert via volume mount or reloaded secret
<br>

## TODO
<br>

### Functional Verification (Post-Provision)
- [ ] Validate that Vault Identity Entities are created for each control plane node
- [ ] Confirm bootstrap token is written to `/etc/vault.d/bootstrap-token`
- [ ] Check that Vault Agent successfully authenticates and renders:
  - [ ] apiserver cert/key
  - [ ] apiserver-kubelet-client cert/key
  - [ ] front-proxy-client cert/key
- [ ] Verify service reload is triggered when certs are rendered
- [ ] Confirm systemd unit `vault-agent.service` is enabled and running
<br>

### Policy Hardening
- [ ] **Limit PKI role access** by defining only the exact roles needed per host:
  - Use `path "pki_k8s_issuing/issue/apiserver"` **instead of** `pki_k8s_issuing/issue/*` when possible
- [ ] **Restrict ingress cert issuance** to specific worker nodes:
  - Consider splitting Vault Agent policies by role (`vault-agent-control-plane`, `vault-agent-ingress`)
- [ ] **Bind policies to Vault Entities** using Identity Group Aliases (for dynamic auth methods)
- [ ] Add `allowed_common_names` to Vault PKI roles for stricter SAN enforcement
- [ ] Use `cidr` metadata constraints on token creation to limit IP usage
<br>

### Security & Audit Enhancements
- [ ] Enable audit devices in Vault (`vault audit enable file ...`) and validate token activity per node
- [ ] Add Vault alerting/monitoring for:
  - Token renew failures
  - Certificate expiry
  - Unauthorized issue attempts
- [ ] Rotate bootstrap tokens periodically (scriptable with Ansible)
<br>

### Documentation Follow-up
- [ ] Add section in internal docs for how to revoke or reissue tokens per host
- [ ] Include `vault policy read` / `vault token lookup` examples for debugging
- [ ] Include output example of `vault write` used during agent provisioning for clarity
<br>
---
