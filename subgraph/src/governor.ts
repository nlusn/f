import { Bytes } from "@graphprotocol/graph-ts";
import { ProposalCreated as ProposalCreatedEvent } from "../generated/ProtocolGovernor/ProtocolGovernor";
import { Proposal } from "../generated/schema";
import { getOrCreateMetric, ONE } from "./shared";

export function handleProposalCreated(event: ProposalCreatedEvent): void {
  const id = Bytes.fromByteArray(Bytes.fromBigInt(event.params.proposalId));
  const p = new Proposal(id);
  p.proposalId = event.params.proposalId;
  p.proposer = event.params.proposer;
  p.description = event.params.description;
  p.voteStart = event.params.voteStart;
  p.voteEnd = event.params.voteEnd;
  p.createdAt = event.block.timestamp;
  p.blockNumber = event.block.number;
  p.transactionHash = event.transaction.hash;
  p.save();

  const m = getOrCreateMetric();
  m.totalProposals = m.totalProposals.plus(ONE);
  m.save();
}
