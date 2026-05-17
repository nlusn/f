#!/usr/bin/env bash
#
# Reproducible deployment of the DeFi Super-App to Arbitrum Sepolia.
#
# This script is idempotent in the sense that you can re-run it to redeploy
# to a fresh network. It does NOT attempt to detect already-deployed contracts
# — re-running on the same network will spend gas to deploy a NEW set.
#
# Prereqs:
#   - foundryup installed (forge, cast)
#   - A funded deployer key in $PRIVATE_KEY
#   - All env vars from .env.example exported (or .env sourced)
#
# Usage:
#   ./script/deploy.sh                   # deploy + verify on Arbitrum Sepolia
#   NETWORK=base_sepolia ./script/deploy.sh
#
set -euo pipefail

# Load .env if present (does not override already-exported vars).
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

NETWORK="${NETWORK:-base_sepolia}"

required=(
  PRIVATE_KEY
  TOKEN_A TOKEN_B
  COLLATERAL_TOKEN BORROW_TOKEN
  COLLATERAL_PRICE_FEED BORROW_PRICE_FEED
)
for v in "${required[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Missing required env var: $v" >&2
    echo "See .env.example for the full list." >&2
    exit 1
  fi
done

mkdir -p deployments

echo "==> Deploying to ${NETWORK}..."
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "${NETWORK}" \
  --broadcast \
  --verify \
  -vvvv

echo "==> Running post-deployment verification..."
forge script script/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url "${NETWORK}" \
  -vv | tee deployments/verification-report.txt

echo "==> Done. Addresses in deployments/$(cast chain-id --rpc-url "${NETWORK}").json"
