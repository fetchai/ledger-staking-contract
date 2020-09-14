const {expect} = require('chai');
const {deployTokenContract, dumpToJsonFile, getNetowrk} = require('../utility/utils');
const ERC20Token = artifacts.require("FetERC20Mock");

const manifest_file_name = `${__dirname}/deployment_manifest.json`;
const network = getNetowrk();

contract("Deploy FetERC20Mock contract", async accounts => {
    let token;
    const owner = accounts[0];
    const deployment_manifest = require(manifest_file_name);

    it("deployment execution", async () => {
        token = await deployTokenContract(owner);
        const n = (network in deployment_manifest) ? deployment_manifest[network] : {};
        n.FetERC20Mock = token.address;
        deployment_manifest[network] = n;
        dumpToJsonFile(manifest_file_name, deployment_manifest, null, 2);
    });
});
