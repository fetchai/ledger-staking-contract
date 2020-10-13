#!/usr/bin/python3
from brownie import Staking, web3, accounts

def main():
    accounts.load('foundation')
    Staking.deploy("0xb4dfa9f9dd69dfC1bC3255981fd05eFDA503Ca3a", 0x00, 21508300, 100, {'from': accounts[0]})
