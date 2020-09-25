const {expect} = require('chai');
const {deployTokenContract, dumpToJsonFile, getNetwork} = require('../utility/utils');
const ERC20Token = artifacts.require("FetERC20Mock");

const manifest_file_name = `${__dirname}/deployment_manifest.json`;
const network = getNetwork();
const erc20key = "";
contract("Deploy FetERC20Mock contract", async accounts => {
    let token;
    const owner = accounts[0];
    const deployment_manifest = require(manifest_file_name);

    it("deployment execution", async () => {
        const n = (network in deployment_manifest) ? deployment_manifest[network] : {};

        if (n.FetERC20Mock == null) {
            n.FetERC20Mock = {};
        }

        token = await deployTokenContract(owner);
        n.FetERC20Mock.contract_address = token.address;
        deployment_manifest[network] = n;
        dumpToJsonFile(manifest_file_name, deployment_manifest, null, 2);
    });
});
