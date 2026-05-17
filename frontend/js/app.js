// Main entry — wires up tabs, wallet, and per-page modules.

import { CHAIN } from "./config.js";
import { connect, switchChain, onChange, getState } from "./wallet.js";
import { shortAddr } from "./ui.js";

import * as swap from "./pages/swap.js";
import * as vault from "./pages/vault.js";
import * as lend from "./pages/lend.js";
import * as govern from "./pages/govern.js";

const pages = { swap, vault, lend, govern };

// ── Tab routing ──────────────────────────────────────────────────────────────
document.querySelectorAll(".tab").forEach((btn) => {
  btn.addEventListener("click", () => {
    const key = btn.dataset.tab;
    document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t === btn));
    document
      .querySelectorAll(".page")
      .forEach((p) => p.classList.toggle("active", p.id === `page-${key}`));
  });
});

// ── Wallet controls ──────────────────────────────────────────────────────────
document.getElementById("connect-btn").addEventListener("click", connect);
document.getElementById("switch-btn").addEventListener("click", switchChain);

// ── React to wallet state changes ────────────────────────────────────────────
function render(s) {
  const account = document.getElementById("account-pill");
  const network = document.getElementById("network-pill");
  const banner = document.getElementById("network-banner");
  const connectBtn = document.getElementById("connect-btn");

  if (s.connected) {
    account.textContent = shortAddr(s.account);
    account.className = "pill pill-ok";
    connectBtn.textContent = "Connected";
    connectBtn.disabled = true;
  } else {
    account.textContent = "—";
    account.className = "pill pill-muted";
    connectBtn.textContent = "Connect wallet";
    connectBtn.disabled = false;
  }

  if (s.chainId == null) {
    network.textContent = "not connected";
    network.className = "pill pill-muted";
    banner.classList.add("hidden");
  } else if (s.correctChain) {
    network.textContent = CHAIN.name;
    network.className = "pill pill-ok";
    banner.classList.add("hidden");
  } else {
    network.textContent = `chain ${s.chainId}`;
    network.className = "pill pill-warn";
    banner.classList.remove("hidden");
  }

  for (const p of Object.values(pages)) p.onWallet(s);
}

// Initial render + subscribe.
render(getState());
onChange(render);

// Init pages (attaches their event listeners).
for (const p of Object.values(pages)) p.init();
