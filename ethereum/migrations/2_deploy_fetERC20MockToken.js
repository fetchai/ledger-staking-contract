const { FET_ERC20 } = require('../utility/constants');

let token = artifacts.require("FetERC20Mock");

async function makeDeployment(deployer, network) {
	await deployer.deploy(token, FET_ERC20._name, FET_ERC20._symbol, FET_ERC20._initialSupply, FET_ERC20._decimals);
}

module.exports = (deployer, network) => {
    deployer.then(async () => {
        await makeDeployment(deployer, network);
    });
};
