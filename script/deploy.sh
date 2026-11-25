#!/usr/bin/env bash
# Deploy helper for Payday Splitter. Keeps the forge flags in one place.
# Set DEPLOYER_PRIVATE_KEY first, then run one step at a time:
#   ./script/deploy.sh base              # step 1, MockUSDC on Base Sepolia
#   ./script/deploy.sh predict-reactive  # predict the reactive address, prints REACTIVE
#   ./script/deploy.sh vault             # step 2, vault on Base Sepolia (needs REACTIVE, TOKEN)
#   ./script/deploy.sh lasna             # step 3, reactive on Lasna (needs VAULT)
#   ./script/deploy.sh setup-lasna       # step 4a, set recipient on Lasna (needs REACTIVE, VAULT)
#   ./script/deploy.sh setup-base        # step 4b, demo salary on Base Sepolia (needs TOKEN, VAULT)
# Order matters. The vault must exist before the reactive contract subscribes
# to it, so predict the reactive address first, deploy the vault with that
# address as its callback sender, then deploy the reactive. The deployer
# address is derived from DEPLOYER_PRIVATE_KEY with cast.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_RPC="https://sepolia.base.org"
LASNA_RPC="https://lasna-rpc.rnk.dev"

: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY first}"

run() {
  local script="$1" rpc="$2"
  shift 2
  forge script "script/${script}.s.sol" --rpc-url "$rpc" --broadcast "$@"
}

case "${1:-}" in
  base)
    run DeployBase "$BASE_RPC"
    ;;
  predict)
    DEPLOYER=$(cast wallet address "$DEPLOYER_PRIVATE_KEY")
    NONCE=$(cast nonce --rpc-url "$BASE_RPC" "$DEPLOYER")
    echo "Deployer: $DEPLOYER (Base Sepolia nonce $NONCE)"
    echo "Predicted vault address:"
    cast compute-address --nonce "$NONCE" "$DEPLOYER"
    echo "Export it before the next step, for example: export VAULT=<address above>"
    ;;
  predict-reactive)
    DEPLOYER=$(cast wallet address "$DEPLOYER_PRIVATE_KEY")
    NONCE=$(cast nonce --rpc-url "$LASNA_RPC" "$DEPLOYER")
    echo "Deployer: $DEPLOYER (Lasna nonce $NONCE)"
    echo "Predicted reactive address:"
    cast compute-address --nonce "$NONCE" "$DEPLOYER"
    echo "Export it before the next step, for example: export REACTIVE=<address above>"
    echo "Send no other Lasna transaction from the deployer until the reactive is deployed."
    ;;
  lasna)
    : "${VAULT:?set VAULT to the PaydayVault address first (deploy the vault before the reactive)}"
    VAULT="$VAULT" run DeployLasna "$LASNA_RPC"
    ;;
  vault)
    : "${REACTIVE:?set REACTIVE to the predicted reactive address first (run ./script/deploy.sh predict-reactive)}"
    : "${TOKEN:?set TOKEN to the MockUSDC address first}"
    REACTIVE="$REACTIVE" TOKEN="$TOKEN" run DeployVault "$BASE_RPC"
    ;;
  setup-base)
    : "${TOKEN:?set TOKEN to the MockUSDC address first}"
    : "${VAULT:?set VAULT to the PaydayVault address first}"
    TOKEN="$TOKEN" VAULT="$VAULT" run SetupDemoBase "$BASE_RPC"
    ;;
  setup-lasna)
    : "${REACTIVE:?set REACTIVE to the Lasna reactive address first}"
    : "${VAULT:?set VAULT to the PaydayVault address first}"
    REACTIVE="$REACTIVE" VAULT="$VAULT" run SetupDemoLasna "$LASNA_RPC"
    ;;
  *)
    echo "Usage: $0 {base|predict|predict-reactive|lasna|vault|setup-base|setup-lasna}"
    exit 1
    ;;
esac
