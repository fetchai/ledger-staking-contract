# Deployment of production contracts

This folder contains scripts which can be used to deploy the contract to networks defined in the `truffle-config.js` file.

Each scripts is dedicated to deploy only it's own contract, and resulting address of the deployed contract will be written in to the `deployment_manifest.json ` manifest file in order to keep the record what has been deployed and where. The manifest file located in the same folder as the scripts.

The primary purpose of the he deployment information from the manifest file is to support repetitive re-deployments of contracts with depend on another contract(s) which are not desired to be re-deployed but rather **reused** (= use already deployed contracts).

**IMPORTANT: Changes made in the `deployment_manifest.json` file shall be committed in to GIT repository in order to maintain permanent record fo deployed contracts and so support their re-usability in the future.**

## Build of the contracts
This step (build of all necessary contracts) is executed automatically by all other relevant truffle commands, so
strictly speaking it is not necessary to execute it manually.

* Build all necessary contracts (using parameters specified in the `truffle-config.js`):
  ```lang=sh
  truffle build
  ```

## General usage of `truffle`:

This **must** be executed from the **parent** folder where `truffle-config.js` file is located:


General usage:
```lang=sh
truffle test [--network NETWORK_NAME] <deploy/DEPLOY_SCRIPT.js>
```


### `FetERC20Mock` contract deployment:
Bellow are examples of the deployment commands:

* Deployment to to the `development` (= default) network:
  ```lang=sh
  truffle test deploy/deploy_fetERC20Mock.js
  ```

* Deployment to the `kovan` network
  ```lang=sh
  truffle test --network kovan deploy/deploy_fetERC20Mock.js
  ```

### `Staking` contract deployment:

NOTE 1: This contract depends on already deployed instance of the `FetERC20Mock` contract, this it needs to be deployed **first** as described in section above.

NOTE 2: This script will read the address of deployed  `FetERC20Mock` contract from `deployment_manifest.json` file, thus whichever address of `FetERC20Mock` contract is present for the `network` in manifest file, it will be used for the deployment of `Staking` contract, no questions asked. If the `FetERC20Mock` contract address is **not** present for given `netowrk` in manifest file, then deployent of `Staking` contract will **fail** with approriate error message. 

Bellow are examples of the deployment commands:

* Deployment to to the `development` (= default) network:
  ```lang=sh
  truffle test deploy/deploy_staking.js
  ```

* Deployment to the `kovan` network
  ```lang=sh
  truffle test --network kovan deploy/deploy_staking.js
  ```
