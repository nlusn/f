import { formatUnits, parseUnits } from "https://esm.sh/ethers@6.13.4";
import { ADDRESSES, TOKEN_META } from "../config.js";
import { read, erc20 } from "../contracts.js";
import { withToast, toast } from "../ui.js";

const $ = (sel) => document.querySelector(sel);

const asset = { addr: ADDRESSES.borrowToken, ...TOKEN_META.tokenB };
let walletState = { connected: false, signer: null, provider: null };

export function init() {
  $("#vault-deposit-btn").addEventListener("click", doDeposit);
  $("#vault-withdraw-btn").addEventListener("click", doWithdraw);
}

export function onWallet(s) {
  walletState = s;
  $("#vault-deposit-btn").disabled = !(s.connected && s.correctChain);
  $("#vault-withdraw-btn").disabled = !(s.connected && s.correctChain);
  refresh();
}

async function refresh() {
  if (!walletState.account) {
    $("#vault-shares").textContent = "Connect wallet";
    $("#vault-underlying").textContent = "—";
    return;
  }
  try {
    const vault = read("vault", walletState.provider);
    const shares = await vault.balanceOf(walletState.account);
    const underlying = await vault.convertToAssets(shares);
    $("#vault-shares").textContent = `${formatUnits(shares, 18)} shares`;
    $("#vault-underlying").textContent =
      `${formatUnits(underlying, asset.decimals)} ${asset.symbol}`;
  } catch (e) {
    $("#vault-shares").textContent = "—";
    console.error(e);
  }
}

async function doDeposit() {
  const v = $("#vault-deposit-amount").value;
  if (!v || Number(v) <= 0) return toast.warning("Enter an amount");
  const amount = parseUnits(v, asset.decimals);

  await withToast("Approve", async () => {
    const token = erc20(asset.addr, walletState.signer);
    const allow = await token.allowance(walletState.account, ADDRESSES.yieldVault);
    if (allow >= amount) return;
    return await token.approve(ADDRESSES.yieldVault, amount);
  });
  await withToast("Deposit", async () => {
    const vault = read("vault", walletState.signer);
    return await vault.deposit(amount, walletState.account);
  });
  refresh();
}

async function doWithdraw() {
  const v = $("#vault-withdraw-amount").value;
  if (!v || Number(v) <= 0) return toast.warning("Enter share amount");
  const shares = parseUnits(v, 18);
  await withToast("Withdraw", async () => {
    const vault = read("vault", walletState.signer);
    return await vault.redeem(shares, walletState.account, walletState.account);
  });
  refresh();
}
