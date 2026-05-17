import { Bytes } from "@graphprotocol/graph-ts";
import { AchievementMinted as AchievementMintedEvent } from "../generated/AchievementNFT/AchievementNFT";
import { Achievement } from "../generated/schema";
import { getOrCreateMetric, ONE } from "./shared";

export function handleAchievementMinted(event: AchievementMintedEvent): void {
  const id = Bytes.fromByteArray(Bytes.fromBigInt(event.params.tokenId));
  const a = new Achievement(id);
  a.tokenId = event.params.tokenId;
  a.recipient = event.params.recipient;
  a.achievementType = event.params.achievementType;
  a.tier = event.params.tier;
  a.blockNumber = event.block.number;
  a.blockTimestamp = event.block.timestamp;
  a.transactionHash = event.transaction.hash;
  a.save();

  const m = getOrCreateMetric();
  m.totalAchievements = m.totalAchievements.plus(ONE);
  m.save();
}
