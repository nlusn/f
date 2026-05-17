// Toast notifications + human-friendly error mapping.

const container = () => document.getElementById("toast-container");

function show(kind, title, detail) {
  const el = document.createElement("div");
  el.className = `toast ${kind}`;
  el.innerHTML = `<strong>${title}</strong>${detail ? `<small>${escape(detail)}</small>` : ""}`;
  container().appendChild(el);
  setTimeout(() => el.remove(), 6000);
}

function escape(s) {
  const div = document.createElement("div");
  div.textContent = String(s);
  return div.innerHTML;
}

export const toast = {
  success: (t, d) => show("success", t, d),
  error: (t, d) => show("error", t, d),
  warning: (t, d) => show("warning", t, d),
  info: (t, d) => show("", t, d),
};

/**
 * Map an ethers / RPC error to a short user-facing message.
 * Avoids leaking raw RPC payloads.
 */
export function describeError(err) {
  // User rejected the prompt in MetaMask.
  if (err?.code === 4001 || err?.code === "ACTION_REJECTED") {
    return "Transaction rejected in wallet.";
  }
  // Reverted on-chain (or simulated to revert).
  if (err?.code === "CALL_EXCEPTION") {
    const reason = err.reason || err.shortMessage || "Transaction reverted";
    return reason;
  }
  // Insufficient native gas funds.
  const msg = (err?.message || err?.shortMessage || "").toLowerCase();
  if (msg.includes("insufficient funds")) {
    return "Insufficient balance for gas.";
  }
  if (msg.includes("user rejected")) {
    return "Transaction rejected in wallet.";
  }
  if (msg.includes("network changed")) {
    return "Network changed mid-transaction — please retry.";
  }
  // Fall back to the short message — never the full RPC payload.
  return err?.shortMessage || err?.message || "Something went wrong.";
}

/** Wraps a write call: toasts on rejection / failure / success. */
export async function withToast(label, fn) {
  try {
    const result = await fn();
    if (result?.wait) {
      toast.info(`${label}: submitted`, result.hash);
      await result.wait();
      toast.success(`${label}: confirmed`);
    } else {
      toast.success(`${label}: done`);
    }
    return result;
  } catch (err) {
    toast.error(`${label} failed`, describeError(err));
    throw err;
  }
}

/** Short hex address: 0x1234…abcd. */
export function shortAddr(a) {
  if (!a) return "—";
  return a.slice(0, 6) + "…" + a.slice(-4);
}

/** Format a unix timestamp as relative ("5m ago"). */
export function timeAgo(ts) {
  const s = Math.floor(Date.now() / 1000) - Number(ts);
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}
