const { BN, time } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');
const fs = require('fs')

const { FET_ERC20 } = require("./constants.js")
const ERC20Token = artifacts.require("FetERC20Mock");


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
    let amountUsed = amount || initialBalance;
    for (i=0; i < accounts.length; i++) {
        await token.approve(instance.address, amountUsed, {from: accounts[i]});
    }
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

exports.logGasUsed = function (tx_receipt) {
    console.log("gasUsed = " + tx_receipt.receipt.gasUsed);
    return tx_receipt;
}

exports.loadFromJsonFile = (path) => {
    return JSON.parse(fs.readFileSync(path).toString('utf8'));
}


exports.dumpToJsonFile = (path, obj, ...contents) => {
    fs.writeFileSync(path, JSON.stringify(obj, ...contents));
}

exports.getNetowrk = () => {
    const network_idx = process.argv.indexOf('--network');
    return (network_idx < 0) ? "development" : process.argv[network_idx + 1];
}
