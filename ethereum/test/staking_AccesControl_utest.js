const {BN, constants, expectEvent, expectRevert, time} = require('@openzeppelin/test-helpers');
const {assert, expect} = require('chai');
const {deployTokenContract} = require('../utility/utils');
const {Contract} = require("../utility/constants")

const stakingContract = artifacts.require("StakingMock");

contract("staking", async accounts => {
    let instance, token;
    const owner = accounts[0];
    const notOwner = accounts[1];
    const delegate = accounts[2];


    const deployInstance = async function (token) {
        let newInstance = await stakingContract.new(token.address);
        return newInstance
    };


    before(async () => {
        token = await deployTokenContract(owner, accounts);
    });


    beforeEach(async () => {
        instance = await deployInstance(token);
    });


    describe("AccessControl", function () {

        it("should correctly mark the admin role", async () => {
            assert.isTrue(await instance.hasRole.call(Contract.Status.DEFAULT_ADMIN_ROLE, owner));
        });

        it("should correctly mark non-owners", async () => {
            assert.isFalse(await instance.hasRole.call(Contract.Status.DEFAULT_ADMIN_ROLE, notOwner));
            assert.isFalse(await instance.hasRole.call(Contract.Status.DEFAULT_ADMIN_ROLE, delegate));
            assert.isFalse(await instance.hasRole.call(Contract.Status.DELEGATE_ROLE, notOwner));
            // The `delegate` address shall not be registered in `DLEGATE_ROLE` just yet(straight after contract deployment)
            assert.isFalse(await instance.hasRole.call(Contract.Status.DELEGATE_ROLE, delegate));
        });
    });
});
