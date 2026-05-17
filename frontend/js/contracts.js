// Ethers Contract factory bound to the current signer/provider.

import { Contract } from "https://esm.sh/ethers@6.13.4";
import { ADDRESSES } from "./config.js";
import {
  ERC20_ABI,
  PROTOCOL_TOKEN_ABI,
  AMM_ABI,
  VAULT_ABI,
  LENDING_ABI,
  GOVERNOR_ABI,
} from "./abis.js";

const ZERO = "0x0000000000000000000000000000000000000000";

function assertConfigured(name, addr) {
  if (!addr || addr === ZERO) {
    throw new Error(
      `${name} address not configured — edit frontend/js/config.js after deployment.`,
    );
  }
}

/** Returns a read-only contract bound to a provider. */
export function read(name, runner) {
  const map = {
    protocolToken: [ADDRESSES.protocolToken, PROTOCOL_TOKEN_ABI],
    amm: [ADDRESSES.amm, AMM_ABI],
    vault: [ADDRESSES.yieldVault, VAULT_ABI],
    lending: [ADDRESSES.lendingPool, LENDING_ABI],
    governor: [ADDRESSES.governor, GOVERNOR_ABI],
    tokenA: [ADDRESSES.tokenA, ERC20_ABI],
    tokenB: [ADDRESSES.tokenB, ERC20_ABI],
    borrowToken: [ADDRESSES.borrowToken, ERC20_ABI],
  };
  const cfg = map[name];
  if (!cfg) throw new Error(`Unknown contract ${name}`);
  assertConfigured(name, cfg[0]);
  return new Contract(cfg[0], cfg[1], runner);
}

/** ERC-20 helper bound to an arbitrary address. */
export function erc20(addr, runner) {
  assertConfigured("erc20", addr);
  return new Contract(addr, ERC20_ABI, runner);
}
