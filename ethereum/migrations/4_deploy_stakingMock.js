let Staking = artifacts.require("StakingMock");
let ERC20Token = artifacts.require("FetERC20Mock");

module.exports = function(deployer) {
  deployer.deploy(Staking, ERC20Token.address);
};
