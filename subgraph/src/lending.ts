import { Bytes } from "@graphprotocol/graph-ts";
import {
  CollateralDeposited as CollateralDepositedEvent,
  CollateralWithdrawn as CollateralWithdrawnEvent,
  Borrowed as BorrowedEvent,
  Repaid as RepaidEvent,
  Liquidated as LiquidatedEvent,
  InterestAccrued as InterestAccruedEvent,
} from "../generated/LendingPool/LendingPool";
import { LoanPosition } from "../generated/schema";
import { getOrCreateMetric, ONE, ZERO } from "./shared";

function loadOrCreatePosition(user: Bytes): LoanPosition {
  let p = LoanPosition.load(user);
  if (p == null) {
    p = new LoanPosition(user);
    p.user = user;
    p.collateral = ZERO;
    p.debt = ZERO;
    p.lastEvent = "";
    p.lastUpdate = ZERO;
  }
  return p as LoanPosition;
}

export function handleCollateralDeposited(event: CollateralDepositedEvent): void {
  const p = loadOrCreatePosition(event.params.user);
  p.collateral = event.params.newTotal;
  p.lastEvent = "CollateralDeposited";
  p.lastUpdate = event.block.timestamp;
  p.save();
}

export function handleCollateralWithdrawn(event: CollateralWithdrawnEvent): void {
  const p = loadOrCreatePosition(event.params.user);
  p.collateral = event.params.newTotal;
  p.lastEvent = "CollateralWithdrawn";
  p.lastUpdate = event.block.timestamp;
  p.save();
}

export function handleBorrowed(event: BorrowedEvent): void {
  const p = loadOrCreatePosition(event.params.user);
  // First borrow ever (debt was 0)?
  if (p.debt.equals(ZERO)) {
    const m = getOrCreateMetric();
    m.totalLoansOpened = m.totalLoansOpened.plus(ONE);
    m.save();
  }
  p.debt = event.params.newDebt;
  p.lastEvent = "Borrowed";
  p.lastUpdate = event.block.timestamp;
  p.save();
}

export function handleRepaid(event: RepaidEvent): void {
  const p = loadOrCreatePosition(event.params.user);
  p.debt = event.params.remainingDebt;
  p.lastEvent = "Repaid";
  p.lastUpdate = event.block.timestamp;
  p.save();
}

export function handleLiquidated(event: LiquidatedEvent): void {
  const p = loadOrCreatePosition(event.params.borrower);
  // Subtract liquidated amounts; LendingPool emits the post-hoc state via
  // separate CollateralWithdrawn / Repaid events too, but this keeps the row
  // up-to-date even in single-event subscribers.
  p.collateral = p.collateral.minus(event.params.collateralSeized);
  if (p.collateral.lt(ZERO)) p.collateral = ZERO;
  p.debt = p.debt.minus(event.params.debtRepaid);
  if (p.debt.lt(ZERO)) p.debt = ZERO;
  p.lastEvent = "Liquidated";
  p.lastUpdate = event.block.timestamp;
  p.save();

  const m = getOrCreateMetric();
  m.totalLiquidations = m.totalLiquidations.plus(ONE);
  m.save();
}

export function handleInterestAccrued(event: InterestAccruedEvent): void {
  const p = loadOrCreatePosition(event.params.user);
  p.debt = event.params.newDebt;
  p.lastEvent = "InterestAccrued";
  p.lastUpdate = event.block.timestamp;
  p.save();
}
