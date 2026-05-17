import { formatUnits, parseUnits } from "https://esm.sh/ethers@6.13.4";
import { ADDRESSES, TOKEN_META } from "../config.js";
import { read, erc20 } from "../contracts.js";
import { gql, Q_RECENT_SWAPS } from "../subgraph.js";
import { withToast, shortAddr, timeAgo, toast, describeError } from "../ui.js";

const $ = (sel) => document.querySelector(sel);

const tokens = [
  { key: "tokenA", addr: ADDRESSES.tokenA, ...TOKEN_META.tokenA },
  { key: "tokenB", addr: ADDRESSES.tokenB, ...TOKEN_META.tokenB },
];

let walletState = { connected: false, signer: null, provider: null };

export function init() {
  // Token-in dropdown
  const sel = $("#swap-token-in");
  sel.innerHTML = tokens.map((t) => `<option value="${t.key}">${t.symbol}</option>`).join("");
  document
    .querySelectorAll("[data-token-a-symbol]")
    .forEach((n) => (n.textContent = tokens[0].symbol));
  document
    .querySelectorAll("[data-token-b-symbol]")
    .forEach((n) => (n.textContent = tokens[1].symbol));

  $("#swap-amount-in").addEventListener("input", quote);
  sel.addEventListener("change", quote);
  $("#swap-btn").addEventListener("click", doSwap);

  refreshReserves();
  refreshRecentSwaps();
}

export function onWallet(s) {
  walletState = s;
  $("#swap-btn").disabled = !(s.connected && s.correctChain);
  refreshReserves();
}

async function refreshReserves() {
  try {
    const provider = walletState.provider;
    if (!provider) {
      $("#reserve-a").textContent = "Connect wallet";
      $("#reserve-b").textContent = "";
      return;
    }
    const amm = read("amm", provider);
    const [a, b] = await Promise.all([amm.reserveA(), amm.reserveB()]);
    $("#reserve-a").textContent = `${formatUnits(a, tokens[0].decimals)} ${tokens[0].symbol}`;
    $("#reserve-b").textContent = `${formatUnits(b, tokens[1].decimals)} ${tokens[1].symbol}`;
  } catch (e) {
    $("#reserve-a").textContent = "—";
    $("#reserve-b").textContent = describeError(e);
  }
}

async function quote() {
  const amount = $("#swap-amount-in").value;
  const inKey = $("#swap-token-in").value;
  const tokenIn = tokens.find((t) => t.key === inKey);
  const tokenOut = tokens.find((t) => t.key !== inKey);
  const out = $("#swap-amount-out");
  if (!amount || Number(amount) <= 0 || !walletState.provider) {
    out.value = "";
    return;
  }
  try {
    const amm = read("amm", walletState.provider);
    const amountIn = parseUnits(amount, tokenIn.decimals);
    const amountOut = await amm.getAmountOut(tokenIn.addr, amountIn);
    out.value = `${formatUnits(amountOut, tokenOut.decimals)} ${tokenOut.symbol}`;
    $("#swap-spot").textContent = `1 ${tokenIn.symbol} ≈ ${(
      Number(formatUnits(amountOut, tokenOut.decimals)) / Number(amount)
    ).toFixed(6)} ${tokenOut.symbol}`;
  } catch (e) {
    out.value = describeError(e);
  }
}

async function doSwap() {
  const amount = $("#swap-amount-in").value;
  const inKey = $("#swap-token-in").value;
  const tokenIn = tokens.find((t) => t.key === inKey);
  if (!amount || Number(amount) <= 0) return toast.warning("Enter an amount");

  const amountIn = parseUnits(amount, tokenIn.decimals);

  await withToast("Approve", async () => {
    const token = erc20(tokenIn.addr, walletState.signer);
    const current = await token.allowance(walletState.account, ADDRESSES.amm);
    if (current >= amountIn) return; // already approved
    return await token.approve(ADDRESSES.amm, amountIn);
  });

  await withToast("Swap", async () => {
    const amm = read("amm", walletState.signer);
    const deadline = Math.floor(Date.now() / 1000) + 600;
    // 0.5% slippage on the quote
    const quoted = await amm.getAmountOut(tokenIn.addr, amountIn);
    const minOut = (quoted * 995n) / 1000n;
    return await amm.swap(tokenIn.addr, amountIn, minOut, walletState.account, deadline);
  });

  refreshReserves();
  refreshRecentSwaps();
}

async function refreshRecentSwaps() {
  const body = $("#recent-swaps");
  try {
    const data = await gql(Q_RECENT_SWAPS, { limit: 10 });
    if (!data.swaps?.length) {
      body.innerHTML = `<tr><td colspan="4" class="muted">No swaps yet.</td></tr>`;
      return;
    }
    body.innerHTML = data.swaps
      .map((s, i) => {
        const tIn =
          s.tokenIn.toLowerCase() === ADDRESSES.tokenA.toLowerCase() ? tokens[0] : tokens[1];
        const tOut =
          s.tokenOut.toLowerCase() === ADDRESSES.tokenA.toLowerCase() ? tokens[0] : tokens[1];
        return `<tr style="--i:${i}">
          <td>${timeAgo(s.blockTimestamp)}</td>
          <td>${shortAddr(s.user)}</td>
          <td>${formatUnits(s.amountIn, tIn.decimals)} ${tIn.symbol}</td>
          <td>${formatUnits(s.amountOut, tOut.decimals)} ${tOut.symbol}</td>
        </tr>`;
      })
      .join("");
  } catch (e) {
    body.innerHTML = `<tr><td colspan="4" class="muted">Subgraph unavailable: ${describeError(e)}</td></tr>`;
  }
}
