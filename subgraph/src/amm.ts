import {
  Swapped as SwappedEvent,
  LiquidityAdded as LiquidityAddedEvent,
  LiquidityRemoved as LiquidityRemovedEvent,
} from "../generated/AMM/AMM";
import { Swap, LiquidityEvent } from "../generated/schema";
import { eventId, getOrCreateMetric, ONE } from "./shared";

export function handleSwapped(event: SwappedEvent): void {
  const s = new Swap(eventId(event));
  s.user = event.params.user;
  s.tokenIn = event.params.tokenIn;
  s.tokenOut = event.params.tokenOut;
  s.amountIn = event.params.amountIn;
  s.amountOut = event.params.amountOut;
  s.blockNumber = event.block.number;
  s.blockTimestamp = event.block.timestamp;
  s.transactionHash = event.transaction.hash;
  s.save();

  const m = getOrCreateMetric();
  m.totalSwaps = m.totalSwaps.plus(ONE);
  m.save();
}

export function handleLiquidityAdded(event: LiquidityAddedEvent): void {
  const e = new LiquidityEvent(eventId(event));
  e.provider = event.params.provider;
  e.action = "ADD";
  e.amountA = event.params.amountA;
  e.amountB = event.params.amountB;
  e.lpAmount = event.params.lpMinted;
  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();

  const m = getOrCreateMetric();
  m.totalLiquidityEvents = m.totalLiquidityEvents.plus(ONE);
  m.save();
}

export function handleLiquidityRemoved(event: LiquidityRemovedEvent): void {
  const e = new LiquidityEvent(eventId(event));
  e.provider = event.params.provider;
  e.action = "REMOVE";
  e.amountA = event.params.amountA;
  e.amountB = event.params.amountB;
  e.lpAmount = event.params.lpBurned;
  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();

  const m = getOrCreateMetric();
  m.totalLiquidityEvents = m.totalLiquidityEvents.plus(ONE);
  m.save();
}
