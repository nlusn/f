import {
  Deposited as DepositedEvent,
  Withdrawn as WithdrawnEvent,
  YieldHarvested as YieldHarvestedEvent,
} from "../generated/YieldVault/YieldVault";
import { VaultEvent } from "../generated/schema";
import { eventId, getOrCreateMetric, ZERO } from "./shared";

export function handleDeposited(event: DepositedEvent): void {
  const v = new VaultEvent(eventId(event));
  v.user = event.params.receiver;
  v.action = "DEPOSIT";
  v.assets = event.params.assets;
  v.shares = event.params.shares;
  v.blockNumber = event.block.number;
  v.blockTimestamp = event.block.timestamp;
  v.transactionHash = event.transaction.hash;
  v.save();

  const m = getOrCreateMetric();
  m.totalVaultDeposits = m.totalVaultDeposits.plus(event.params.assets);
  m.save();
}

export function handleWithdrawn(event: WithdrawnEvent): void {
  const v = new VaultEvent(eventId(event));
  v.user = event.params.owner;
  v.action = "WITHDRAW";
  v.assets = event.params.assets;
  v.shares = event.params.shares;
  v.blockNumber = event.block.number;
  v.blockTimestamp = event.block.timestamp;
  v.transactionHash = event.transaction.hash;
  v.save();
}

export function handleYieldHarvested(event: YieldHarvestedEvent): void {
  const v = new VaultEvent(eventId(event));
  v.user = event.params.strategist;
  v.action = "YIELD_HARVEST";
  v.assets = event.params.amount;
  v.shares = ZERO;
  v.blockNumber = event.block.number;
  v.blockTimestamp = event.block.timestamp;
  v.transactionHash = event.transaction.hash;
  v.save();
}
