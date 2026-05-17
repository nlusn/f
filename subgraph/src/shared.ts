import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { ProtocolMetric } from "../generated/schema";

export const ZERO = BigInt.fromI32(0);
export const ONE = BigInt.fromI32(1);

/**
 * Return the global ProtocolMetric, creating it on first touch.
 * Singleton id = "global".
 */
export function getOrCreateMetric(): ProtocolMetric {
  let m = ProtocolMetric.load("global");
  if (m == null) {
    m = new ProtocolMetric("global");
    m.totalSwaps = ZERO;
    m.totalLiquidityEvents = ZERO;
    m.totalVaultDeposits = ZERO;
    m.totalLoansOpened = ZERO;
    m.totalLiquidations = ZERO;
    m.totalAchievements = ZERO;
    m.totalProposals = ZERO;
  }
  return m as ProtocolMetric;
}

/**
 * Stable id for an event row: <txHash>-<logIndex>.
 */
export function eventId(ev: ethereum.Event): Bytes {
  return ev.transaction.hash.concatI32(ev.logIndex.toI32());
}
