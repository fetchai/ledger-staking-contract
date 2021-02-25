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

However, it is expected to have the `.secrets_infura_project_id` text file located in the user's home directory (stored
in the `HOME` environment variable), containing single line with infura project Id, for instance:
```text
f1e067bfafd642a185865ca93e26063f
```

Run the following command-line to query all the excess funds transfers:
```shell
node query_excess_funds.js
```

Bellow is an example of the script's resulting output in stdout:
```text
Current block:  11646414
Number of " LiquidityDeposited " events:  1257
Number of " RewardsPoolTokenTopUp " events:  2
[0] 0x00fd47A1ff317758A8ca3D72cEeA64c2a7A5aE13 :  100 [FET] = 100000000000000000000 [Canonical FET], {https://etherscan.io/tx/0x8572138ca1679ac5f8217c77f0bb9e3c4847f3a3be7abc39b457d73053312f3e}
[1] 0x46340b20830761efd32832A74d7169B29FEB9758 :  19741.6 [FET] = 19741600000000000000000 [Canonical FET], {https://etherscan.io/tx/0xe80233d7b2039a208a5e591ad765b149f3f3a2aef1633224c3d5bc25cfa3bcd2}
[2] 0xD551234Ae421e3BCBA99A0Da6d736074f22192FF :  712 [FET] = 712000000000000000000 [Canonical FET], {https://etherscan.io/tx/0x2fd2516fee34aab7537a65c54c61538887f856d3f5c2802ce7e360701746e930}
[3] 0x1f6Cc10fABfc7C1eB295CAF357c53774535A65B6 :  29414 [FET] = 29414000000000000000000 [Canonical FET], {https://etherscan.io/tx/0x3c36c70919e2320d3f14e79481814862a4a9f331429ac68c1be31df7522663a7}
[4] 0xaCd10bF8480D0977C5e89D08221b5796e21Be591 :  7440 [FET] = 7440000000000000000000 [Canonical FET], {https://etherscan.io/tx/0xc89081a5bace423af19d405c030baccf100a408f66f1a07d6a464e78923645a1}
[5] 0x18E52C0b6326238A1C1606fb95ad2B30Ac3De912 :  42458.35779865 [FET] = 42458357798650000000000 [Canonical FET], {https://etherscan.io/tx/0x77037c7b91a290e474a515726966025273c5e2ccdaf63fac62a1d33360487402}
[6] 0xd04B4167f7F50346501Ef1dCA7353ac1e4a02afC :  1000 [FET] = 1000000000000000000000 [Canonical FET], {https://etherscan.io/tx/0xfdae1b491f10a97cc5e2d4199882716b26765e54b3e0b884cf63e4cedfdbbb93}
Number of excess transfer events: 7
Aggregated value: 100865.95779865 [FET] = 100865957798650000000000 [Canonical FET]
SUCCESS: calculated aggregate equals to expected value.
```

The execution will query all `Transfer` events from ERC20 contract filtered with **to** (transfer destination) address 
set to address of Staking Contract.
It also queries all `LiquidityDeposited` and `RewardsPoolTokenTopUp` events from Staking Contract and finds
logical exclusion group containing such ERC20 `Transfer` events of which associated transaction hash is **NOT** present
in transactions associated with `LiquidityDeposited` and `RewardsPoolTokenTopUp` events.
Scripts does consistency check by comparing aggregated value of all detected excess transfers against **expected** excess
funds value calculated from relevant Staking Contract state variables.


## 3. Query Phoenix Users Who Need Attention: 
This will query all users which added or removed their stake **AFTER** their last call of `Phoenix.claimRewards()`. 

**IMPORTANT:** It is expected to have the `.secrets_infura_project_id` text file located in the user's home directory 
(directory represented by `HOME` environment variable), containing single line with infura project Id, for instance
bellow is an EXAMPLE of the content of that file:
```text
f1e067bfafd642a185865ca93e26063f
```

Run the following command-line to query all the excess funds transfers:
```shell
node phoenix_users_needing_attention.js
```

Bellow is an EXAMPLE of the script's resulting output in stdout:
```text
Since block:  11889029 (Phoenix deployment)
Current block:  11925168
Number of " BindStake " events:  208
Number of " UnbindStake " events:  4
============================================================================
USER ADDRESS, ADDED/REMOVED STAKE, [CLAIMED-AT-BLOCK / STAKED-FROM-BLOCK-ON]
----------------------------------------------------------------------------
0x00Aa19E6Fa5e55756c776D004F25ffA1FdC69f14: 14940 FET, [11889219 / 11889249]
0x3cC9e3AB3679D8f4D0640C87E25FE377C4B51d72: 114812 FET, [11889640 / 11889670]
...
0xb1E8EF9D3732C55790411B341FC2164A87C433fc: 5058 FET, [11924684 / 11924774]
0x7b9C94068BFc878Dd1bdF4D6C696682A9442c109: -5371.918295490226130729 FET, [11899646 / 11899985]
----------------------------------------------------------------------------
========================================
All relevant events for double-checking:
(+) {0x00Aa19E6Fa5e55756c776D004F25ffA1FdC69f14}[claimed-at:11889219][staked-at:11889249]: added amount  : 14940 FET
(+) {0x3cC9e3AB3679D8f4D0640C87E25FE377C4B51d72}[claimed-at:11889640][staked-at:11889670]: added amount  : 114812 FET
...
(+) {0xb1E8EF9D3732C55790411B341FC2164A87C433fc}[claimed-at:11924684][staked-at:11924774]: added amount  : 5058 FET
(-) {0x7b9C94068BFc878Dd1bdF4D6C696682A9442c109}[claimed-at:11899646][staked-at:11899985]: removed amount: 5371.918295490226130729 FET
```
