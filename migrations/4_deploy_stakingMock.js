const { FET_ERC20, Contract } = require("../utility/constants.js");
const Staking = artifacts.require("StakingMock");
const ERC20Token = artifacts.require("FetERC20Mock");

module.exports = function(deployer, network) {
    if (!network.includes("development")) {
        return;
    }

    deployer.deploy(Staking,
        ERC20Token.address,
        Contract.Status.INITIAL_INTEREST_RATE_PER_BLOCK,
        Contract.Status.INITIAL_PAUSED_SINCE_BLOCK,
        Contract.Status.INITIAL_LOCK_PERIOD_FOR_UNBOUND_STAKE);
};
