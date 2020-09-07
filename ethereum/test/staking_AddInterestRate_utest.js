const {BN, constants, expectEvent, expectRevert, time} = require('@openzeppelin/test-helpers');
const {assert, expect} = require('chai');
const {FET_ERC20} = require("../utility/constants.js");
const {deployTokenAccounts, approveAll} = require('../utility/utils');

const stakingContract = artifacts.require("StakingMock");


contract("staking", async accounts => {
    let instance, token;
    // ERC20 balance given to every account when deploying the token
    const initialBalance = new BN('100000').mul(FET_ERC20.multiplier);
    const owner = accounts[0];
    const notOwner = accounts[1];
    const delegate = accounts[2];
    const amount = new BN('1').mul(FET_ERC20.multiplier);


    const deployInstance = async function (token) {
        let newInstance = await stakingContract.new(token.address);
        return newInstance
    };


    before(async () => {
        token = await deployTokenAccounts(owner, accounts, initialBalance);
    });


    beforeEach(async () => {
        instance = await deployInstance(token);
        await approveAll(token, instance, accounts, initialBalance);
    });


    describe("Add Liquidity", function () {
        it("basic", async () => {
            const curr_block_num = await instance._blockNumber.call();

            receipt = await instance.addLiquidity(amount, curr_block_num, {from: notOwner});
            await expectEvent.inLogs(receipt.logs, "LiquidityInjected", {
                stakerAddress : notOwner,
                amount: amount
            });

            expect(await instance.getNumberOfLockedFunds(notOwner)).to.be.bignumber.equal(new BN('1'));
            const user_liquidity = await instance._liquidity.call(notOwner, 0);
            //console.log(JSON.stringify(user_liquidity));
            expect(user_liquidity.amount).to.be.bignumber.equal(amount);
            expect(user_liquidity.liquidSinceBlock).to.be.bignumber.equal(curr_block_num);
         });
    });
});
