import { formatUnits, parseUnits } from "https://esm.sh/ethers@6.13.4";
import { ADDRESSES, TOKEN_META } from "../config.js";
import { read, erc20 } from "../contracts.js";
import { withToast, toast } from "../ui.js";

const $ = (sel) => document.querySelector(sel);

const collateral = { addr: ADDRESSES.tokenA, ...TOKEN_META.tokenA };
const borrow = { addr: ADDRESSES.borrowToken, ...TOKEN_META.tokenB };

let walletState = { connected: false, signer: null, provider: null };

export function init() {
  $("#lend-deposit-btn").addEventListener("click", doDeposit);
  $("#lend-borrow-btn").addEventListener("click", doBorrow);
}

export function onWallet(s) {
  walletState = s;
  const ok = s.connected && s.correctChain;
  $("#lend-deposit-btn").disabled = !ok;
  $("#lend-borrow-btn").disabled = !ok;
  refresh();
}

async function refresh() {
  if (!walletState.account) {
    $("#lend-collateral").textContent = "Connect wallet";
    $("#lend-debt").textContent = "—";
    $("#lend-health").textContent = "—";
    return;
  }
  try {
    const lp = read("lending", walletState.provider);
    const pos = await lp.positions(walletState.account);
    const hf = await lp.healthFactor(walletState.account);
    $("#lend-collateral").textContent =
      `${formatUnits(pos.collateral, collateral.decimals)} ${collateral.symbol}`;
    $("#lend-debt").textContent = `${formatUnits(pos.debt, borrow.decimals)} ${borrow.symbol}`;
    // healthFactor is scaled by 1e18; max-uint means "no debt"
    const hfNum = Number(formatUnits(hf, 18));
    $("#lend-health").textContent = hfNum > 1e10 ? "∞ (no debt)" : hfNum.toFixed(3);
  } catch (e) {
    $("#lend-collateral").textContent = "—";
    console.error(e);
  }
}

async function doDeposit() {
  const v = $("#lend-collateral-amount").value;
  if (!v || Number(v) <= 0) return toast.warning("Enter an amount");
  const amount = parseUnits(v, collateral.decimals);

  await withToast("Approve", async () => {
    const t = erc20(collateral.addr, walletState.signer);
    const allow = await t.allowance(walletState.account, ADDRESSES.lendingPool);
    if (allow >= amount) return;
    return await t.approve(ADDRESSES.lendingPool, amount);
  });
  await withToast("Deposit collateral", async () => {
    const lp = read("lending", walletState.signer);
    return await lp.depositCollateral(amount);
  });
  refresh();
}

async function doBorrow() {
  const v = $("#lend-borrow-amount").value;
  if (!v || Number(v) <= 0) return toast.warning("Enter an amount");
  const amount = parseUnits(v, borrow.decimals);
  await withToast("Borrow", async () => {
    const lp = read("lending", walletState.signer);
    return await lp.borrow(amount);
  });
  refresh();
}
