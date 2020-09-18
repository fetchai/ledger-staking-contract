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
    const delegate = accounts[2];
    const amount = new BN('1').mul(FET_ERC20.multiplier);


    before(async () => {
        token = await deployTokenAccounts(owner, accounts, initialBalance);
    });


    beforeEach(async () => {
        instance = await deployStakingMock(token);
        await approveAll(token, instance, accounts, initialBalance);
    });

    describe("Add Interest Rate", function () {
        const rate_100_percent = new BN(10).pow(new BN(18));

        it("basic", async () => {
            const curr_block_num = await instance._blockNumber.call();
            const tx_block_num = curr_block_num.add(new BN('1'));
            const init_idx = await instance._interestRatesNextIdx.call();

            const receipt = await instance.addInterestRate(rate_100_percent, tx_block_num, {from: owner});
            await expectEvent.inLogs(receipt.logs, "NewInterestRate", {
                index: init_idx,
                rate: rate_100_percent,
            });

            expect(await instance._interestRatesNextIdx.call()).to.be.bignumber.equal(init_idx.add(new BN(1)));
            const interest_rate_struct = await instance._interestRates.call(init_idx);
            expect(interest_rate_struct.rate).to.be.bignumber.equal(rate_100_percent);
            expect(interest_rate_struct.sinceBlock).to.be.bignumber.equal(curr_block_num);
        });
    });
});
