const {BN, constants, expectEvent, expectRevert, time} = require('@openzeppelin/test-helpers');
const {assert, expect} = require('chai');
const {deployTokenContract, logGasUsed, deployStakingMock} = require('../utility/utils');
const {Contract} = require("../utility/constants")

const stakingContract = artifacts.require("StakingMock");

contract("staking", async accounts => {
    let instance, token;
    const admin1 = accounts[0];
    const notOwner = accounts[1];
    const delegate = accounts[2];
    const admin2 = accounts[3];

    before(async () => {
        token = await deployTokenContract(admin1);
    });


    beforeEach(async () => {
        instance = await deployStakingMock(token);
    });


    describe("AccessControl", function () {

        it("should correctly mark the admin role", async () => {
            assert.isTrue(await instance.hasRole.call(Contract.Status.DEFAULT_ADMIN_ROLE, admin1));
        });

        it("should correctly mark non-owners", async () => {
            assert.isFalse(await instance.hasRole.call(Contract.Status.DEFAULT_ADMIN_ROLE, notOwner));
            assert.isFalse(await instance.hasRole.call(Contract.Status.DEFAULT_ADMIN_ROLE, delegate));
            assert.isFalse(await instance.hasRole.call(Contract.Status.DELEGATE_ROLE, notOwner));
            // The `delegate` address shall not be registered in `DLEGATE_ROLE` just yet(straight after contract deployment)
            assert.isFalse(await instance.hasRole.call(Contract.Status.DELEGATE_ROLE, delegate));
        });

        it("add additional admin", async () => {
            assert.isFalse(await instance.hasRole.call(Contract.Status.DEFAULT_ADMIN_ROLE, admin2));
            const receipt = await instance.grantRole(Contract.Status.DEFAULT_ADMIN_ROLE, admin2, {from: admin1}).then(logGasUsed);
            assert.isTrue(await instance.hasRole.call(Contract.Status.DEFAULT_ADMIN_ROLE, admin2));
        });

        it("add delegate", async () => {
            assert.isFalse(await instance.hasRole.call(Contract.Status.DELEGATE_ROLE, delegate));
            const receipt = await instance.grantRole(Contract.Status.DELEGATE_ROLE, delegate, {from: admin1}).then(logGasUsed);
            assert.isTrue(await instance.hasRole.call(Contract.Status.DELEGATE_ROLE, delegate));
        });
    });
});
