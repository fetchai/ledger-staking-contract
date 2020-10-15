const { BN, time } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');
const fs = require('fs')
const { FET_ERC20, Contract } = require("./constants.js")

const ERC20Token = artifacts.require("FetERC20Mock");
const StakingMock = artifacts.require("StakingMock");
const Staking = artifacts.require("Staking");


exports.deployTokenContract = async function(owner) {
     return await ERC20Token.new(FET_ERC20._name, FET_ERC20._symbol, FET_ERC20._initialSupply, FET_ERC20._decimals, {from: owner});
};


exports.deployTokenAccounts = async function(owner, accounts, initialBalance) {
    let token = await exports.deployTokenContract(owner);

    if (initialBalance > 0) {
        for (i=0; i < accounts.length; i++) {
            await token.transfer(accounts[i], initialBalance);
        }
    }
    return token;
};


// Approves transfer to the auction for all accounts
exports.approveAll = async function(token, instance, accounts, amount) {
    const amountUsed = amount || initialBalance;
    for (i=0; i < accounts.length; i++) {
        await token.approve(instance.address, amountUsed, {from: accounts[i]});
    }
};


exports.deployStakingMock = async (
    tokenContractInstance,
    interestRatePerBlock = Contract.Status.INITIAL_INTEREST_RATE_PER_BLOCK,
    pausedSinceBlock = Contract.Status.INITIAL_PAUSED_SINCE_BLOCK,
    lockPeriodInBlocks = Contract.Status.INITIAL_LOCK_PERIOD_FOR_UNBOUND_STAKE
    ) => {
    const newInstance = await StakingMock.new(
        tokenContractInstance.address,
        interestRatePerBlock,
        pausedSinceBlock,
        lockPeriodInBlocks);
    return newInstance;
};


exports.getAccessControlRole = function (role_name_str) {
    return web3.utils.soliditySha3(role_name_str);
}


exports.getCurrentBlockNumber = async function () {
    return await web3.eth.getBlockNumber();
}


exports.sleep = function (ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

exports.logGasUsed = function (tx_receipt, methodName=null) {
    const methodDesc = methodName ? `${methodName}(...)` : "";
    console.log(`gasUsed ${methodDesc}: ${tx_receipt.receipt.gasUsed}`);
    return tx_receipt;
}

exports.loadFromJsonFile = (path) => {
    return JSON.parse(fs.readFileSync(path).toString('utf8'));
}


exports.dumpToJsonFile = (path, obj, ...contents) => {
    fs.writeFileSync(path, JSON.stringify(obj, ...contents));
}


exports.getNetwork = () => {
    const network_idx = process.argv.indexOf('--network');
    return (network_idx < 0) ? "development" : process.argv[network_idx + 1];
}


// Advance to targetBlock
exports.waitUntilBlockchainAdvances = async function(do_continue_waiting_if_predicate_callback) {
    const is_ganache = exports.getNetwork() === "development";

    const advanceBlock = is_ganache ?
        async () => {
            await time.advanceBlock();
            return await web3.eth.getBlockNumber();
        }
        :
        async () => {
            let prevBlockNumber = await web3.eth.getBlockNumber();
            for (;;) {
                await exports.sleep(1000);
                const cb = await web3.eth.getBlockNumber();
                if (cb > prevBlockNumber) {
                    return cb;
                }
                prevBlockNumber = cb;
            }
        };

    for (;;) {
        const currentBlockNumber = await advanceBlock();
        if (await do_continue_waiting_if_predicate_callback(currentBlockNumber)) {
            break;
        }
    }
}


exports.advanceToBlock = async (targetBlock) => {
   await exports.waitUntilBlockchainAdvances(async (currentBlock) => {
       return targetBlock > currentBlock;
   });
}


exports.getDeploymentManifestFilePath = () => {
    const manifest_file_path = `${__dirname}/../deploy/deployment_manifest.json`;
    return manifest_file_path;
}


exports.getDeploymentManifest = () => {
    const manifest_file_path = exports.getDeploymentManifestFilePath();
    const manifest = require(manifest_file_path);
    return manifest;
}


exports.getDeploymentManifestForCurrentNetwork = () => {
    const manifest = exports.getDeploymentManifest();
    const network = exports.getNetwork();
    return manifest[network];
}


exports.instantiateContractsFromManifest = async () => {
    const manifest = exports.getDeploymentManifestForCurrentNetwork();
    const contracts = {};

    for (const contract_name in manifest) {

        const contractPrototype = artifacts.require(contract_name);
        const contract_addr = manifest[contract_name].contract_address;
        contracts[contract_name] = await contractPrototype.at(contract_addr);
    }

    return contracts;
}


exports.getCmdlArgs = () => {
    const proc_argv = process.argv;
    let i=0;
    const idx = proc_argv.findIndex((value) => {
        return value === "--";
    });

    if (idx < 0) {
        throw new Error(`The "--" separator missing on commandline`);
    }

    return proc_argv.slice(idx+1);
}
