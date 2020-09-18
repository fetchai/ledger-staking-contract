const { BN, constants, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert, expect } = require('chai');
const { FET_ERC20 } = require("../utility/constants.js");
const { deployTokenAccounts, approveAll, logGasUsed, deployStakingMock } = require('../utility/utils');

const stakingContract = artifacts.require("StakingMock");


contract("staking", async accounts => {
    let instance, token;
    // ERC20 balance given to every account when deploying the token
    const initialBalance = new BN('100000').mul(FET_ERC20.multiplier);
    const owner = accounts[0];
    const notOwner = accounts[1];
    const notOwner2 = accounts[2];
    const stakeAmount = new BN('1').mul(FET_ERC20.multiplier);
    const depositAmount = stakeAmount.mul(new BN('10'));


    before(async () => {
        token = await deployTokenAccounts(owner, accounts, initialBalance);
    });


    beforeEach(async () => {
        instance = await deployStakingMock(token);
        await approveAll(token, instance, accounts, initialBalance);
    });


    describe("bindStake", function () {
        it("basic", async () => {
            //const lockPeriodInBlocks = await instance._lockPeriodInBlocks.call();
            const curr_block_num = await instance._blockNumber.call();

            let receipt = await instance.deposit(depositAmount, curr_block_num, {from: notOwner});
            await expectEvent.inLogs(receipt.logs, "LiquidityDeposited", {
                stakerAddress : notOwner,
                amount: depositAmount
            });
            // BindStake(msg.sender, _amount.principal, _amount.compoundInterest)
            receipt = await instance.bindStake(stakeAmount, curr_block_num, {from: notOwner});
            await expectEvent.inLogs(receipt.logs, "BindStake", {
                stakerAddress : notOwner,
                principal: stakeAmount,
                compoundInterest: new BN('0')
            });

            expect(await instance._accruedGlobalPrincipal.call()).to.be.bignumber.equal(depositAmount);
            const accruedGlobalLiquidity = await instance._accruedGlobalLiquidity.call();
            const accruedGlobalLocked = await instance._accruedGlobalLocked.call();
            const user_liquidity = await instance._liquidity.call(notOwner);
            expect(user_liquidity.principal).to.be.bignumber.equal(depositAmount.sub(stakeAmount));
            expect(user_liquidity.compoundInterest).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLiquidity.principal).to.be.bignumber.equal(depositAmount.sub(stakeAmount));
            expect(accruedGlobalLiquidity.compoundInterest).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLocked.principal).to.be.bignumber.equal(new BN('0'));
            expect(accruedGlobalLocked.compoundInterest).to.be.bignumber.equal(new BN('0'));
        });
    });

    describe("unbindStake", function () {
        const rate_100_percent = new BN(10).pow(new BN(18));
        const num_of_blocks_int = 4;
        const num_of_blocks = new BN(num_of_blocks_int);

        composite = stakeAmount;
        for (i=0; i<num_of_blocks_int; ++i) {
            composite = composite.mul(new BN(2));
        }
        const compound_interest = composite.sub(stakeAmount);
        // The `rewards_pool_amount` will have the same value as expected
        // compound interest at the point of `unbindStake(...)` call bellow.
        const rewards_pool_amount = compound_interest;

        it("basic", async () => {
            const lockPeriodInBlocks = await instance._lockPeriodInBlocks.call();
            const curr_block_num = await instance._blockNumber.call();

            for (i=0; i< num_of_blocks_int; ++i) {
                await instance.addInterestRate(rate_100_percent, curr_block_num.add(new BN(i)), {from: owner}).then(logGasUsed);
            }

            await instance.topUpRewardsPool(rewards_pool_amount, curr_block_num, {from: notOwner2}).then(logGasUsed);
            expect(await instance._rewardsPoolBalance.call()).to.be.bignumber.equal(rewards_pool_amount);

            await instance.deposit(depositAmount, curr_block_num, {from: notOwner}).then(logGasUsed);
            await instance.bindStake(stakeAmount, curr_block_num, {from: notOwner}).then(logGasUsed);

            const new_block_num = curr_block_num.add(num_of_blocks);
            await instance.setBlockNumber(new_block_num);
            expect(await instance._blockNumber.call()).to.be.bignumber.equal(new_block_num);
            const expetced_liquid_since_block = new_block_num.add(lockPeriodInBlocks);

            receipt = await instance.unbindStake(new BN('0'), new_block_num, {from: notOwner}).then(logGasUsed);
            await expectEvent.inLogs(receipt.logs, "UnbindStake", {
                stakerAddress : notOwner,
                liquidSinceBlock: expetced_liquid_since_block,
                principal: stakeAmount,
                compoundInterest: compound_interest
            });

            expect(await instance._rewardsPoolBalance.call()).to.be.bignumber.equal(rewards_pool_amount);
            expect(await instance._accruedGlobalPrincipal.call()).to.be.bignumber.equal(depositAmount);

            const user_liquidity = await instance._liquidity.call(notOwner);
            expect(user_liquidity.principal).to.be.bignumber.equal(depositAmount.sub(stakeAmount));
            expect(user_liquidity.compoundInterest).to.be.bignumber.equal(new BN('0'));

            const accruedGlobalLiquidity = await instance._accruedGlobalLiquidity.call();
            expect(accruedGlobalLiquidity.principal).to.be.bignumber.equal(depositAmount.sub(stakeAmount));
            expect(accruedGlobalLiquidity.compoundInterest).to.be.bignumber.equal(new BN('0'));

            const accruedGlobalLocked = await instance._accruedGlobalLocked.call();
            expect(accruedGlobalLocked.principal).to.be.bignumber.equal(stakeAmount);
            expect(accruedGlobalLocked.compoundInterest).to.be.bignumber.equal(compound_interest);

            const ret = await instance.getLockedAssetsForUser(notOwner);
            expect(ret.principal.length).to.be.equal(1);
            expect(ret.compoundInterest.length).to.be.equal(1);
            expect(ret.liquidSinceBlock.length).to.be.equal(1);

            expect(ret.principal[0]).to.be.bignumber.equal(stakeAmount);
            expect(ret.compoundInterest[0]).to.be.bignumber.equal(compound_interest);
            expect(ret.liquidSinceBlock[0]).to.be.bignumber.equal(expetced_liquid_since_block);
         });
    });
});
