const {expect} = require('chai');
const {deployTokenContract} = require('../utility/utils');

contract("FetERC20MockTest", async accounts => {
    let token;
    const owner = accounts[0];

    before(async () => {
        token = await deployTokenContract(owner);
    });

    describe("FET token", function () {
        it("should result in a totalSupply of 1152997575000000000000000000, matching the deployed ERC20 on etherscan", async () => {
            expect(await token.decimals()).to.be.bignumber.equal('18');
            expect(await token.totalSupply()).to.be.bignumber.equal('1152997575000000000000000000')
        });
    });
});
