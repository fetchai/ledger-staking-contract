# Usage

## 1. Install dependencies
```shell
npm install
```
> NOTE: Tested on node `v14.8.0`, but it should work on quite wide range of versions around that.

## 2. Query the Excess Funds
This queries all excess funds transfers (= all direct ERC20 `transfer(...)` transactions transferring FET tokens
directly to address of Staking Contract).

The query is made by script (see bellow) which contains all static data hardcoded in = addresses of ERC20 & Staking
contracts, deployment blocks for both contracts, and WebSocket URL for Ethereum mainnet.

However, it is expected to have the `.secrets_infura_project_id` text file located in the PARENT (= `../`) folder,
containing single line with infura project Id, for instance:
```text
f1e067bfafd642a185865ca93e26063f
```

Run the following command-line to query all the excess funds transfers:
```shell
node query_excess_funds.js
```

Bellow is an example of the script resulting output in stdout:
```text
Number of " LiquidityDeposited " events:  1251
Number of " RewardsPoolTokenTopUp " events:  2
excess transfer[ 0 ]:  100 [FET] = 100000000000000000000 [Canonical FET] | {https://etherscan.io/tx/0x8572138ca1679ac5f8217c77f0bb9e3c4847f3a3be7abc39b457d73053312f3e}
excess transfer[ 1 ]:  19741.6 [FET] = 19741600000000000000000 [Canonical FET] | {https://etherscan.io/tx/0xe80233d7b2039a208a5e591ad765b149f3f3a2aef1633224c3d5bc25cfa3bcd2}
excess transfer[ 2 ]:  712 [FET] = 712000000000000000000 [Canonical FET] | {https://etherscan.io/tx/0x2fd2516fee34aab7537a65c54c61538887f856d3f5c2802ce7e360701746e930}
excess transfer[ 3 ]:  29414 [FET] = 29414000000000000000000 [Canonical FET] | {https://etherscan.io/tx/0x3c36c70919e2320d3f14e79481814862a4a9f331429ac68c1be31df7522663a7}
excess transfer[ 4 ]:  7440 [FET] = 7440000000000000000000 [Canonical FET] | {https://etherscan.io/tx/0xc89081a5bace423af19d405c030baccf100a408f66f1a07d6a464e78923645a1}
excess transfer[ 5 ]:  42458.35779865 [FET] = 42458357798650000000000 [Canonical FET] | {https://etherscan.io/tx/0x77037c7b91a290e474a515726966025273c5e2ccdaf63fac62a1d33360487402}
Number of excess transfer events: 6
Aggregated value: 99865.95779865 [FET] = 99865957798650000000000 [Canonical FET]
SUCCESS: calculated aggregate equals to expected value.
```

The execution will query all `Transfer` events from ERC20 contract filtered with **to** (transfer destination) address 
set to address of Staking Contract.
It also queries all `LiquidityDeposited` and `RewardsPoolTokenTopUp` events from Staking Contract and finds
logical exclusion group containing such ERC20 `Transfer` events of which associated transaction hash is **NOT** present
in transactions associated with `LiquidityDeposited` and `RewardsPoolTokenTopUp` events.
Scripts does consistency check by comparing aggregated value of all detected excess transfers against **expected** excess
funds value calculated from relevant Staking Contract state variables.
