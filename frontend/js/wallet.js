// MetaMask connection + wrong-network detection.
// We use ethers v6 from esm.sh so no bundler is needed.

import { BrowserProvider } from "https://esm.sh/ethers@6.13.4";
import { CHAIN } from "./config.js";
import { toast, describeError, shortAddr } from "./ui.js";

const state = {
  provider: null,
  signer: null,
  account: null,
  chainId: null,
  listeners: new Set(),
};

export function onChange(fn) {
  state.listeners.add(fn);
  return () => state.listeners.delete(fn);
}

function emit() {
  for (const fn of state.listeners) {
    try {
      fn(getState());
    } catch (e) {
      console.error("listener error:", e);
    }
  }
}

export function getState() {
  return {
    provider: state.provider,
    signer: state.signer,
    account: state.account,
    chainId: state.chainId,
    correctChain: state.chainId === CHAIN.id,
    connected: !!state.account,
  };
}

export async function connect() {
  if (!window.ethereum) {
    toast.error("No wallet detected", "Install MetaMask to continue.");
    return;
  }

  try {
    const provider = new BrowserProvider(window.ethereum);
    const accounts = await provider.send("eth_requestAccounts", []);
    const net = await provider.getNetwork();

    state.provider = provider;
    state.signer = await provider.getSigner();
    state.account = accounts[0];
    state.chainId = Number(net.chainId);

    // Subscribe to wallet events (idempotent — only attach once).
    if (!window.__defi_app_listeners) {
      window.ethereum.on("accountsChanged", (accs) => {
        state.account = accs[0] ?? null;
        if (!state.account) {
          state.signer = null;
          toast.warning("Wallet disconnected");
        }
        emit();
      });
      window.ethereum.on("chainChanged", (hex) => {
        state.chainId = parseInt(hex, 16);
        emit();
      });
      window.__defi_app_listeners = true;
    }

    toast.success("Wallet connected", shortAddr(state.account));
    emit();
  } catch (err) {
    toast.error("Connect failed", describeError(err));
  }
}

/** Prompt MetaMask to switch to Arbitrum Sepolia; add the chain if unknown. */
export async function switchChain() {
  if (!window.ethereum) {
    toast.error("No wallet detected");
    return;
  }
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: CHAIN.hexId }],
    });
  } catch (err) {
    // 4902 = unknown chain → add it
    if (err.code === 4902) {
      try {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [
            {
              chainId: CHAIN.hexId,
              chainName: CHAIN.name,
              nativeCurrency: CHAIN.nativeCurrency,
              rpcUrls: [CHAIN.rpcUrl],
              blockExplorerUrls: [CHAIN.explorer],
            },
          ],
        });
      } catch (addErr) {
        toast.error("Failed to add chain", describeError(addErr));
      }
    } else {
      toast.error("Switch failed", describeError(err));
    }
  }
}
