const {expect} = require('chai');
const {deployTokenContract, dumpToJsonFile, getNetowrk} = require('../utility/utils');
const ERC20Token = artifacts.require("FetERC20Mock");
const stakingContract = artifacts.require("StakingMock");

const manifest_file_name = `${__dirname}/deployment_manifest.json`;
const network = getNetowrk();

contract("Deploy Staking contract", async accounts => {
    let token;
    const owner = accounts[0];
    const deployment_manifest = require(manifest_file_name);

    it("deployment execution", async () => {
        const n = (network in deployment_manifest) ? deployment_manifest[network] : {};
        const token_addr = n.FetERC20Mock;
        if (!token_addr) {
            throw Error(`Address for "FetERC20Mock" contract is NOT found in the "${manifest_file_name}" for the "${network}" network.`);
        }
        staking_contract = await stakingContract.new(token_addr, {from: owner});
        n.Staking = staking_contract.address;
        deployment_manifest[network] = n;
        dumpToJsonFile(manifest_file_name, deployment_manifest, null, 2);
    });
});
