import { formatUnits } from "https://esm.sh/ethers@6.13.4";
import { read } from "../contracts.js";
import { PROPOSAL_STATE } from "../abis.js";
import { gql, Q_PROPOSALS } from "../subgraph.js";
import { withToast, toast, shortAddr, describeError } from "../ui.js";

const $ = (sel) => document.querySelector(sel);

let walletState = { connected: false, signer: null, provider: null };

export function init() {
  $("#gov-delegate-btn").addEventListener("click", doDelegate);
  refreshProposals();
}

export function onWallet(s) {
  walletState = s;
  $("#gov-delegate-btn").disabled = !(s.connected && s.correctChain);
  refreshUser();
  refreshProposals();
}

async function refreshUser() {
  if (!walletState.account) {
    $("#gov-balance").textContent = "Connect wallet";
    $("#gov-votes").textContent = "—";
    $("#gov-delegate").textContent = "—";
    return;
  }
  try {
    const tok = read("protocolToken", walletState.provider);
    const [bal, votes, delegate] = await Promise.all([
      tok.balanceOf(walletState.account),
      tok.getVotes(walletState.account),
      tok.delegates(walletState.account),
    ]);
    $("#gov-balance").textContent = `${formatUnits(bal, 18)} PROTO`;
    $("#gov-votes").textContent = `${formatUnits(votes, 18)} PROTO`;
    $("#gov-delegate").textContent =
      delegate === "0x0000000000000000000000000000000000000000"
        ? "(none — delegate to self to enable voting)"
        : shortAddr(delegate);
  } catch (e) {
    console.error(e);
  }
}

async function doDelegate() {
  await withToast("Delegate", async () => {
    const tok = read("protocolToken", walletState.signer);
    return await tok.delegate(walletState.account);
  });
  refreshUser();
}

async function refreshProposals() {
  const host = $("#proposal-list");
  let proposals;
  try {
    const data = await gql(Q_PROPOSALS);
    proposals = data.proposals;
  } catch (e) {
    host.innerHTML = `<p class="muted">Subgraph unavailable: ${describeError(e)}</p>`;
    return;
  }
  if (!proposals?.length) {
    host.innerHTML = `<p class="muted">No proposals yet.</p>`;
    return;
  }

  // Resolve live state for each proposal via Governor.state().
  const provider = walletState.provider ?? null;
  host.innerHTML = "";
  let i = 0;
  for (const p of proposals) {
    let state = "unknown";
    if (provider) {
      try {
        const gov = read("governor", provider);
        const s = await gov.state(p.proposalId);
        state = PROPOSAL_STATE[Number(s)] ?? "unknown";
      } catch (e) {
        state = "unknown";
      }
    }
    const card = document.createElement("div");
    card.className = "proposal";
    card.style.setProperty("--i", i++);
    card.innerHTML = `
      <div class="proposal-head">
        <strong>Proposal #${BigInt(p.proposalId).toString().slice(0, 8)}…</strong>
        <span class="proposal-state state-${state}">${state}</span>
      </div>
      <div class="proposal-desc">${escapeHtml(p.description || "(no description)")}</div>
      <div class="proposal-meta muted">
        by ${shortAddr(p.proposer)} · voting ${state === "Active" ? "now" : `closes block ${p.voteEnd}`}
      </div>
      <div class="proposal-votes">
        <button class="btn btn-primary" data-vote="1">For</button>
        <button class="btn btn-secondary" data-vote="0">Against</button>
        <button class="btn btn-secondary" data-vote="2">Abstain</button>
      </div>
    `;
    card.querySelectorAll("button[data-vote]").forEach((btn) => {
      btn.disabled = !(walletState.connected && walletState.correctChain && state === "Active");
      btn.addEventListener("click", () => castVote(p.proposalId, Number(btn.dataset.vote)));
    });
    host.appendChild(card);
  }
}

async function castVote(proposalId, support) {
  if (!walletState.signer) return toast.warning("Connect wallet first");
  await withToast("Vote", async () => {
    const gov = read("governor", walletState.signer);
    return await gov.castVote(proposalId, support);
  });
  refreshProposals();
}

function escapeHtml(s) {
  const div = document.createElement("div");
  div.textContent = String(s);
  return div.innerHTML;
}
