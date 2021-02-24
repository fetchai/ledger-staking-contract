const Web3 = require('web3');
const fs = require('fs');
const { BN } = require('bn.js');
const { Decimal } = require('decimal.js');
const path = require('path');

const decimalPrecision = 50;
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

const web3 = new Web3(endpoint);


class Contract {
    constructor(filename, address, startBlock=null) {
        const abi = require(path.join(dir, filename)).abi;
        this.startBlock = startBlock;
        this.contract = new web3.eth.Contract(abi, address);
    }
}


class Principal {
    constructor(value, block) {
        this.value = new BN(value);
        this.block = block;
    }

    clone() {
        return new Principal(this.value, this.block);
    }
}

class PhoenixUserDist {
    constructor(distributions_web3_array_response) {
        this.lastRewardBlock = parseInt(distributions_web3_array_response[0]);
        this.rewardDebt = new BN(distributions_web3_array_response[1]);
        this.FETStaked = new BN(distributions_web3_array_response[2]);
        this.isEnrolled = distributions_web3_array_response[3];
    }
}


class User {
    constructor() {
    this.events = [];
    this.principal = new Principal(0, 0);
    this.principal_history = [];
    }
}


const token = new Contract('IERC20.json', '0x2e1E15C44Ffe4Df6a0cb7371CD00d5028e571d14');
const staking = new Contract('Staking.json', '0x351baC612B50e87B46e4b10A282f632D41397DE2', 11061460);
const phoenix = new Contract('Phoenix.json', '0xe5146Ba42448d1cebe19a7dB52EBAA102821171e', 11889029);


async function main () {
    const curent_block = await web3.eth.getBlockNumber();
    console.log("Current block: ", curent_block);

    const retval = new Object();
    retval.staking = {};
    retval.staking.events_list = [];
    retval.staking.events_dict = {};
    retval.users_to_handle = {}

    const staking_event_names = ["BindStake", "UnbindStake"];
    for (let i = 0; i<staking_event_names.length; ++i) {
        const evt_name = staking_event_names[i];
        await staking.contract.getPastEvents(evt_name, {
            fromBlock: phoenix.startBlock,
            toBlock: "latest",
            },
            (error, events) => {
                if (error) {
                    console.log("error: ", error);
                    throw error;
                }
                retval.staking.events_list = retval.staking.events_list.concat(events);
                const evts_dict = retval.staking.events_dict;

                console.log("Number of \"", evt_name, "\" events: ", events.length);
                for (let i = 0; i < events.length; ++i) {
                    const e = events[i];

                    if (e.removed) {
                        continue;
                    }

                    let user;
                    if (e.returnValues.stakerAddress in evts_dict) {
                        user = evts_dict[e.returnValues.stakerAddress];
                    } else {
                        user = new User();
                        evts_dict[e.returnValues.stakerAddress] = user;
                    }

                    user.events.push(e);
                    if (e.event == "BindStake") {
                        user.principal.value.add(new BN(e.returnValues.principal));
                    }
                    else if (e.event == "UnbindStake") {
                        user.principal.value.sub(new BN(e.returnValues.principal));
                    }

                    user.principal_history.push(user.principal.clone())
                }
            });
    }

    const evts = retval.staking.events_list;
    for (let i=0; i< evts.length; ++i) {
        const e = evts[i];
        let userDist;
        try {
            userDist = new PhoenixUserDist(await phoenix.contract.methods.distributions(e.returnValues.stakerAddress).call());
        } catch (e) {
            console.log("EXCEPTION: ", e);
        }


        if (userDist.lastRewardBlock == 0 || !userDist.isEnrolled) {
            continue;
        }

        if (userDist.lastRewardBlock <= e.blockNumber) {
            if (e.event == "BindStake") {
                console.log(`(+) {${e.returnValues.stakerAddress}}[claimed-at:${userDist.lastRewardBlock}][staked-at:${e.blockNumber}]: added amount  : ${canonicalFetToFet(e.returnValues.principal)} FET`);
            } else if (e.event == "UnindStake") {
                console.log(`(-) {${e.returnValues.stakerAddress}}[claimed-at:${userDist.lastRewardBlock}][staked-at:${e.blockNumber}]: removed amount: ${canonicalFetToFet(e.returnValues.principal)} FET`);
            }
        }
        //console.log(`{${e.returnValues.stakerAddress}}@${e.event}[${e.blockNumber}]: ${canonicalFetToFet(e.returnValues.principal)}`);
    }

    //const aggregate = new BN("0");

    //const events = retval.erc20.events_list;
    //const staking_evts_dict = retval.staking.events_dict;
    //const excess_funds_events_list = [];
    //retval.exces_funds_events_list = excess_funds_events_list;

    //for (let i=0; i< events.length; ++i) {
    //    const e = events[i];
    //    if (! (e.transactionHash in staking_evts_dict)) {
    //        excess_funds_events_list.push(e);
    //        const transfer_amount = new BN(e.returnValues.value);
    //        console.log(`[${excess_funds_events_list.length - 1}] ${e.returnValues.from} : `, canonicalFetToFet(transfer_amount).toString(), "[FET] =", transfer_amount.toString(), `[Canonical FET], {https://etherscan.io/tx/${e.transactionHash}}`);
    //        aggregate.iadd(transfer_amount);
    //    }
    //}

    //dumpToJsonFile(`${dir}/events.json`, retval, null, "  ");

    //const principal = new BN(await staking.methods._accruedGlobalPrincipal().call());
    //const rewards_pool_balance = new BN(await staking.methods.getRewardsPoolBalance().call());
    //const balance = new BN(await token.methods.balanceOf(staking_contract_address).call());
    //const expected_excess_funds_amount = balance.sub(principal.add(rewards_pool_balance));
    //const expected_excess_funds_amount_dec = canonicalFetToFet(expected_excess_funds_amount);
    //const aggregateDec = canonicalFetToFet(aggregate);

    //console.log("Number of excess transfer events:", excess_funds_events_list.length);
    //console.log("Aggregated value:", aggregateDec.toString(), "[FET] =", aggregate.toString(), "[Canonical FET]");

    //if (aggregate.eq(expected_excess_funds_amount)) {
    //    console.log("SUCCESS: calculated aggregate equals to expected value.");
    //} else {
    //    console.log("Expected value  :", expected_excess_funds_amount_dec.toString(), "[FET] =", expected_excess_funds_amount.toString(), "[Canonical FET]");
    //    console.log("FAILURE: calculated aggregate and expected value DIFFER!");
    //}

    web3.currentProvider.connection.close();
}

main();
