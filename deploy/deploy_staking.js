const {expect} = require('chai');
const prompt = require('prompt');
const {deployTokenContract, dumpToJsonFile, getNetwork} = require('../utility/utils');

const stakingContract = artifacts.require("Staking");

const manifest_file_name = `${__dirname}/deployment_manifest.json`;
const network = getNetwork();

contract("Deploy Staking contract", async accounts => {
    let token;
    const owner = accounts[0];
    const deployment_manifest = require(manifest_file_name);

    it("deployment execution", async () => {
        const n = (network in deployment_manifest) ? deployment_manifest[network] : {};
        const params = n.Staking.constructor_params;

        const missing_attributes = [];

        if (params.interestRatePerBlock == null) {
            missing_attributes.push("interestRatePerBlock");
        }

        if (params.pausedSinceBlock == null) {
            missing_attributes.push("pausedSinceBlock");
        }

        if (params.lockPeriodInBlocks == null) {
            missing_attributes.push("lockPeriodInBlocks");

        }

        if (missing_attributes.length > 0) {
            throw new Error(`The following mandatory attributes [${missing_attributes.join(", ")}] are missing in the "${network}.Staking.contructor_params" section in the "${manifest_file_name}" file. Exiting ...`);
        }

        let token_addr = params.ERC20Address;
        if (!token_addr) {
            console.log(`There is no "${network}.Staking.contructor_params.ERC20Address" attribute provided => going to try to use address from the "FetERC20Mock" config section.`);
            if (n.FetERC20Mock == null || !n.FetERC20Mock.contract_address ) {
                throw new Error(`Address for "FetERC20Mock" contract has not been found in the "${manifest_file_name}" for the "${network}" network configuration.`);
            }

            token_addr = n.FetERC20Mock.contract_address;
            n.Staking.constructor_params.ERC20Address = token_addr;
        }

        const schema = {
            properties: {
                accepted: {
                    description: 'Are above contract input parameters correct [y/N]?',
                    type: 'string',
                    default: 'N',
                    required: false,
                    hidden: false
                }
            }
        };

        console.log(`Network: ${network}`);
        console.log(`Input parameters for the contract constructor:\n${JSON.stringify(n.Staking.constructor_params, null, 2)}`);
        prompt.start();
        const { accepted } = await prompt.get(schema);
        if (accepted.toLowerCase() !== 'y') {
            console.log('Parameters rejected by user.\nNO action has been taken.\nExiting ...');
            return;
        }

        staking_contract = await stakingContract.new(
            token_addr,
            params.interestRatePerBlock,
            params.pausedSinceBlock,
            params.lockPeriodInBlocks,
            {from: owner});

        n.Staking.contract_address = staking_contract.address;
        deployment_manifest[network] = n;
        dumpToJsonFile(manifest_file_name, deployment_manifest, null, 2);
    });
});
