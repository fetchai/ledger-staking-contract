const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert, expect } = require('chai');
const { FET_ERC20 } = require("../utility/constants.js");
const { deployTokenAccounts, approveAll, deployStakingMock } = require('../utility/utils');

const stakingContract = artifacts.require("StakingMock");


contract("staking", async accounts => {
    let instance, token;
    // ERC20 balance given to every account when deploying the token
    const initialBalance = new BN('100000').mul(FET_ERC20.multiplier);
    const owner = accounts[0];
    const notOwner = accounts[1];
    const notOwner2 = accounts[2];
    const amount = new BN('1').mul(FET_ERC20.multiplier);


    before(async () => {
        token = await deployTokenAccounts(owner, accounts, initialBalance);
    });


    beforeEach(async () => {
        instance = await deployStakingMock(token);
        await approveAll(token, instance, accounts, initialBalance);
    });


    describe("Deposit", function () {
        it("deposit as owner #1", async () => {
            const curr_block_num = await instance._blockNumber.call();
            const user = notOwner;

            receipt = await instance.deposit(amount, curr_block_num, {from: user});
            await expectEvent.inLogs(receipt.logs, "LiquidityDeposited", {
                stakerAddress : user,
                amount: amount
            });

            expect(await instance._accruedGlobalPrincipal.call()).to.be.bignumber.equal(amount);
            const accruedGlobalLiquidity = await instance._accruedGlobalLiquidity.call();
            const accruedGlobalLocked = await instance._accruedGlobalLocked.call();
            const user_liquidity = await instance._liquidity.call(user);
            //console.log(JSON.stringify(user_liquidity));
            expect(user_liquidity.principal).to.be.bignumber.equal(amount);
            expect(user_liquidity.compoundInterest).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLiquidity.principal).to.be.bignumber.equal(amount);
            expect(accruedGlobalLiquidity.compoundInterest).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLocked.principal).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLocked.compoundInterest).to.be.bignumber.equal(new BN('0'));
        });

        it("add more as owner #2", async () => {
            let curr_block_num = await instance._blockNumber.call();

            receipt = await instance.deposit(amount, curr_block_num, {from: notOwner});
            await expectEvent.inLogs(receipt.logs, "LiquidityDeposited", {
                stakerAddress : notOwner,
                amount: amount
            });


            curr_block_num = curr_block_num.add(new BN('100'));
            await instance.setBlockNumber(curr_block_num);
            expect(await instance._blockNumber.call()).to.be.bignumber.equal(curr_block_num);

            const user = notOwner2;
            receipt = await instance.deposit(amount, curr_block_num, {from: user});
            await expectEvent.inLogs(receipt.logs, "LiquidityDeposited", {
                stakerAddress : user,
                amount: amount
            });

            expect(await instance._accruedGlobalPrincipal.call()).to.be.bignumber.equal(amount.add(amount));
            const accruedGlobalLiquidity = await instance._accruedGlobalLiquidity.call();
            const accruedGlobalLocked = await instance._accruedGlobalLocked.call();
            const user_liquidity = await instance._liquidity.call(user);

            expect(user_liquidity.principal).to.be.bignumber.equal(amount);
            expect(user_liquidity.compoundInterest).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLiquidity.principal).to.be.bignumber.equal(amount.add(amount));
            expect(accruedGlobalLiquidity.compoundInterest).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLocked.principal).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLocked.compoundInterest).to.be.bignumber.equal(new BN('0'));
        });
    });
});
