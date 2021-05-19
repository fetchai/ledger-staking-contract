const Web3 = require('web3');
const fs = require('fs');
const { BN } = require('bn.js');
const { Decimal } = require('decimal.js');
const path = require('path');

const decimalPrecision = 100;
const fetErc20CanonicalMultiplier = new Decimal('1e18');

function dumpToJsonFile(path, obj, ...contents) {
    fs.writeFileSync(path, JSON.stringify(obj, ...contents));
}

function canonicalFetToFet(canonicalVal) {
    const origPrecision = Decimal.precision
    Decimal.set({ precision: decimalPrecision })
    try {
        return (new Decimal(canonicalVal.toString())).div(fetErc20CanonicalMultiplier)
    }
    finally {
        Decimal.set({ precision: origPrecision })
    }
}

const dir = __dirname;
const home_dir = process.env.HOME;
const infuraProjectId = fs.readFileSync(path.join(home_dir, '.secrets_infura_project_id')).toString().trim();
const _endpoint = 'wss://mainnet.infura.io/ws/v3';
const endpoint = `${_endpoint}/${infuraProjectId}`;

//const web3 = new Web3(endpoint);
const web3 = new Web3(new Web3.providers.WebsocketProvider(
        endpoint,
        {
            clientConfig:{
                maxReceivedFrameSize: 10000000000,
                maxReceivedMessageSize: 10000000000,
            }
        }));


class Contract {
    constructor(filename, address, startBlock=null) {
        const abi = require(path.join(dir, filename)).abi;
        this.startBlock = startBlock;
        this.contract = new web3.eth.Contract(abi, address);
    }
}


class Asset {
    constructor(principal, compountInterest) {
        this.principal = new BN(principal); // necessary to avoid returning original `value` BN instance
        this.compoundInterest = new BN(compountInterest); // necessary to avoid returning original `value` BN instance

        this.principalFET = canonicalFetToFet(this.principal);
        this.compoundInterestFET = canonicalFetToFet(this.compoundInterest);
        this.compositeFET = this.principalFET.add(this.compoundInterestFET);
    }

    clone() {
        return new Asset(this.principal, this.compoundInterest);
    }
}


class InterestRate {
    constructor(sinceBlock, ratePerBlockCanonical) {
        this.sinceBlock = new BN(sinceBlock); // necessary to avoid returning original `value` BN instance
        this.ratePerBlockCanonical = new BN(ratePerBlockCanonical);
        this.ratePerBlock = canonicalFetToFet(this.ratePerBlockCanonical.toString());
    }

    clone() {
        return new InterestRate(this.sinceBlock, this.ratePerBlockCanonical);
    }
}


class InterestRates {
    constructor(startIdx, nextIdx, ratesMap) {
        this.startIdx = parseInt(startIdx); // necessary to avoid returning original `value` BN instance
        this.nextIdx = parseInt(nextIdx);
        this.ratesMap = {};
        for (const [idx, rate] of Object.entries(ratesMap)) {
            this.ratesMap[idx] = rate.clone();
        }
    }

    //calcCompoundInterest(stake, untilBlock_) {
    //    const principal = canonicalFetToFet(stake.asset.principal);
    //    const existingEompoundInterest = canonicalFetToFet(stake.asset.compoundInterest);
    //    const untilBlock = new BN(untilBlock_);


    //    //if (until_block.lt(stake.sinceBlock)) {
    //    //    return existingEompoundInterest;
    //    //}

    //    let composite = existingEompoundInterest.add(principal);
    //    const _1 = new Decimal("1");

    //    for (let i=stake.sinceInterestRateIndex; i < this.nextIdx; ++i) {
    //        const n = i + 1;
    //        const rate = this.ratesMap[i];
    //        let startBlock = BN.max(stake.sinceBlock, rate.sinceBlock)
    //        let endBlock = untilBlock;

    //        if (n < this.nextIdx) {
    //            const nextRate = this.ratesMap[n];
    //            endBlock = BN.min(endBlock, nextRate.sinceBlock);
    //        }

    //        const num_of_blocks = new Decimal(endBlock.sub(startBlock).toString());
    //        const interestMultiplier = _1.add(rate.ratePerBlock).pow(num_of_blocks);
    //        const accrued_composite = composite.mul(interestMultiplier);
    //        composite = accrued_composite;
    //    }

    //    const compoundInterest = composite.sub(principal);

    //    return compoundInterest;
    //}

    static async queryFromContract() {
        const startIdx = parseInt(await staking.contract.methods._interestRatesStartIdx().call());
        const nextIdx = parseInt(await staking.contract.methods._interestRatesNextIdx().call());

        let rates = {};
        for (let i = startIdx; i < nextIdx; ++i) {
            const r = await staking.contract.methods._interestRates(i).call();
            rates[i] = new InterestRate(r[0], r[1]);
        }

        return new InterestRates(startIdx, nextIdx, rates);
    }

    clone() {
        return new InterestRates(this.startIdx, this.nextIdx, this.ratesMap);
    }
}


class Stake {
    constructor(asset, sinceBlock, sinceInterestRateIndex) {
        this.asset = asset.clone(); // necessary to avoid returning original `value` BN instance
        this.sinceBlock = new BN(sinceBlock); // necessary to avoid returning original `value` BN instance
        this.sinceInterestRateIndex = new BN(sinceInterestRateIndex);
    }

    static async queryFromContract(userAddress) {
        const s = await staking.contract.methods.getStakeForUser(userAddress).call();

        const asset = new Asset(s[0], s[1]);
        return new Stake(asset, s[2], s[3]);
    }

    calcCompoundInterest(interestRates, untilBlock_) {
        const untilBlock = new BN(untilBlock_);

        let composite = new Decimal(this.asset.compositeFET);
        const _1 = new Decimal("1");

        for (let i=this.sinceInterestRateIndex; i < interestRates.nextIdx; ++i) {
            const n = i + 1;
            const rate = interestRates.ratesMap[i];
            let startBlock = BN.max(this.sinceBlock, rate.sinceBlock)
            let endBlock = untilBlock;

            if (n < interestRates.nextIdx) {
                const nextRate = interestRates.ratesMap[n];
                endBlock = BN.min(endBlock, nextRate.sinceBlock);
            }

            const num_of_blocks = new Decimal(endBlock.sub(startBlock).toString());
            const interestMultiplier = _1.add(rate.ratePerBlock).pow(num_of_blocks);
            const accrued_composite = composite.mul(interestMultiplier);
            composite = accrued_composite;
        }

        const compoundInterest = composite.sub(this.asset.principalFET);

        return compoundInterest;
    }

    clone() {
        return new Stake(this.asset, this.sinceBlock, this.sinceInterestRateIndex);
    }
}


class UserAssets {
    constructor(stake, lockedAggr, liquidity) {
        this.stake = stake.clone(); // necessary to avoid returning original `value` BN instance
        this.lockedAggr = lockedAggr.clone();
        this.liquidity = liquidity.clone(); // necessary to avoid returning original `value` BN instance
    }

    static async queryFromContract(userAddress) {
        const stake = await Stake.queryFromContract(userAddress);

        const locA = await staking.contract.methods.getLockedAssetsAggregateForUser(userAddress).call();
        const lockedAggr = new Asset(locA[0], locA[1]);

        const liq = await staking.contract.methods._liquidity(userAddress).call();
        const liquidity = new Asset(liq[0], liq[1]);

        return new UserAssets(stake, lockedAggr, liquidity);
    }

    calcCompoundInterest(interestRates, untilBlock) {
        const compoundInterest_from_stake = this.stake.calcCompoundInterest(interestRates, untilBlock);
        return [compoundInterest_from_stake.add(this.lockedAggr.compoundInterestFET).add(this.liquidity.compoundInterestFET), compoundInterest_from_stake];
    }

    calcPrincipal() {
        return [this.stake.asset.principalFET.add(this.lockedAggr.principalFET).add(this.liquidity.principalFET), this.stake.asset.principalFET];
    }

    clone() {
        return new UserAssets(this.stake, this.lockedAggr, this.liquidity);
    }
}


class User {
    constructor(address) {
        this.address = address;
        this.events = [];
        this.assets = null;
        this.principalFET_whole = null;
        this.principalFET_staked = null;
        this.compoundInterestFET_whole = null;
        this.compoundInterestFET_staked = null;
    }

    async init(interestRates, untilBlock) {
        this.assets = await UserAssets.queryFromContract(this.address);
        [this.principalFET_whole, this.principalFET_staked] = this.assets.calcPrincipal();
        [this.compoundInterestFET_whole, this.compoundInterestFET_staked] = this.assets.calcCompoundInterest(interestRates, untilBlock);
    }
}


const token = new Contract('IERC20.json', '0x2e1E15C44Ffe4Df6a0cb7371CD00d5028e571d14');
const staking = new Contract('Staking.json', '0x351baC612B50e87B46e4b10A282f632D41397DE2', 11061460);


async function main () {
    try {
        const current_block = await web3.eth.getBlockNumber();

        const curr_time = new Date();
        const end_time = new Date("2021-07-15T12:00:00Z");
        if (end_time < curr_time) {
            console.error(`Current time ${curr_time} passed expected decommission time ${end_time} for FET Staking contract.`);
        }
        const average_block_generation_time_secs = 13.17; // [sec/block]
        const estimated_end_block = Math.ceil(current_block + (end_time - curr_time) / (average_block_generation_time_secs * 1000))

        console.log("Since block:", staking.startBlock, "(Staking deployment)");
        console.log("Current block:", current_block);
        console.log("Estimated staking end block:", estimated_end_block);
        console.log("Expected staking end time:", end_time)

        const interestRates = await InterestRates.queryFromContract();
        for (const [idx, rate] of Object.entries(interestRates.ratesMap)) {
            console.log(`[${idx}]: ${rate.ratePerBlock.toString()} [per block], in effect since ${rate.sinceBlock.toString()} block`);
        }

        const retval = new Object();
        retval.staking = {};
        retval.staking.events_list = [];
        retval.staking.users = {};

        const staking_event_names = ["BindStake"];
        for (let i = 0; i < staking_event_names.length; ++i) {
            const evt_name = staking_event_names[i];
            await staking.contract.getPastEvents(evt_name, {
                    fromBlock: staking.startBlock,
                    toBlock: "latest",
                },
                (error, events) => {
                    if (error) {
                        console.log("error: ", error);
                        throw error;
                    }
                    retval.staking.events_list = retval.staking.events_list.concat(events);
                    const users_dict = retval.staking.users;

                    console.log("Number of \"", evt_name, "\" events: ", events.length);
                    for (let i = 0; i < events.length; ++i) {
                        const e = events[i];

                        if (e.removed) {
                            continue;
                        }

                        let user;
                        const userAddr = e.returnValues.stakerAddress;
                        if (e.returnValues.stakerAddress in users_dict) {
                            user = users_dict[userAddr];
                        } else {
                            user = new User(userAddr);
                            users_dict[userAddr] = user;
                        }

                        user.events.push(e);
                    }
                });
        }

        console.log("Number of unique addresses:", Object.keys(retval.staking.users).length);

        console.log(`============================================================================`);
        console.log(`INDEX, USER ADDRESS, PRINCIPAL WHOLE [FET], PRINCIPAL STAKED [FET], COMPOUND INTEREST(LIQUID + LOCKED + STAKED) [FET], COMPOUND INTEREST (STAKED) [FET]`);
        console.log(`----------------------------------------------------------------------------`);
        compound_interest_whole_aggr = canonicalFetToFet("0");
        compound_interest_staked_aggr = canonicalFetToFet("0");
        var i = 0;
        for (const [key, user] of Object.entries(retval.staking.users)) {
            await user.init(interestRates, estimated_end_block);
            compound_interest_whole_aggr = compound_interest_whole_aggr.add(user.compoundInterestFET_whole);
            compound_interest_staked_aggr = compound_interest_staked_aggr.add(user.compoundInterestFET_staked);

            console.log(`${i}, ${key}, ${user.principalFET_whole}, ${user.principalFET_staked}, ${user.compoundInterestFET_whole}, ${user.compoundInterestFET_staked}`);
            ++i;
        }

        console.log(`Compound Interest bellow have been calculated up to estimated end block ${estimated_end_block}:`)
        console.log(`Compound Interest (WHOLE): ${compound_interest_whole_aggr} FET`);
        console.log(`Compound Interest (STAKED): ${compound_interest_staked_aggr} FET`);

        console.log(`----------------------------------------------------------------------------`);
    }
    finally {
        web3.currentProvider.connection.close();
    }
}

main();
