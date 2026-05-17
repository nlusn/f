# ABIs

This directory is populated from the compiled contract artifacts under `../out/`.

After running `forge build` at the repo root, run from `subgraph/`:

```bash
for c in AMM LendingPool YieldVault AchievementNFT; do
  jq '.abi' "../out/${c}.sol/${c}.json" > "abis/${c}.json"
done
```

Then `npm run codegen` will pick them up.
