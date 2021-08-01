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


class Principal {
    constructor(value, block) {
        this.value = new BN(value.toString()); // necessary to avoid returning original `value` BN instance
        this.block = parseInt(block.toString()); // necessary to avoid returning original `value` BN instance
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
    constructor(address) {
        this.address = address;
        this.phoenixDist = null;
        this.events = [];
        this.principal = new Principal(0,0);
        this.principal_after_claim = new Principal(0, 0);
        this.principal_history = [];
        this.principal_delta_history = [];
    }

    async init() {
        this.principal_history = [];
        const s = await staking.contract.methods.getStakeForUser(this.address).call();

        const phoenixDist = new PhoenixUserDist(await phoenix.contract.methods.distributions(this.address).call());
        this.phoenixDist = phoenixDist;
        this.rewards_to_claim = new BN(0);//new BN(await phoenix.contract.methods.getAccumulatedRewards(this.address).call())
        this.principal = new Principal(new BN(s[0]), parseInt(s[2]));
        this.principal_after_claim = new Principal(new BN(0), this.principal.block);
        this.principal_history = [this.principal.clone()];

        for (let j=0; j<this.events.length; ++j) {
            const i = this.events.length - 1 - j;
            const e = this.events[i];
            const prev = this.principal_history[0];
            prev.block = e.blockNumber;

            const p = this.principal_history[0].clone();
            p.block = null;
            this.principal_history.unshift(p);

            if (e.event == "BindStake") {
                const amount = new BN(e.returnValues.principal);
                p.value.isub(amount);
                if (phoenixDist.lastRewardBlock <= e.blockNumber) {
                    this.principal_delta_history.unshift(new Principal(amount, e.blockNumber));
                    this.principal_after_claim.value.iadd(amount);
                }
            } else if (e.event == "UnbindStake") {
                const amount = new BN(e.returnValues.principal);
                p.value.iadd(amount);
                if (phoenixDist.lastRewardBlock <= e.blockNumber) {
                    this.principal_delta_history.unshift(new Principal(amount.neg(), e.blockNumber));
                    this.principal_after_claim.value.isub(amount);
                }
            } else {
                throw Error(`Unexpected event ${e.event} encountered`);
            }
            //console.log(`${this.address}: principal: [${i}]: value=${p.value}, block=${p.block}`);
        }
        //console.log(this);
        //console.log(`${this.address}: added stake: ${canonicalFetToFet(this.principal_after_claim.value)}, [${this.phoenixDist.lastRewardBlock}][${this.principal_delta_history[0].block}]`);
    }
}


const token = new Contract('IERC20.json', '0x7Ef7AdaE450e33B4187fe224cAb1C45d37f7c411');
const staking = new Contract('Staking.json', '0x351baC612B50e87B46e4b10A282f632D41397DE2', 11061460);
const phoenix = new Contract('Phoenix.json', '0xA800DCd36B69D94EA041c1abeFd132Ca4eB5605c', 12226389);


async function main () {
    const curent_block = await web3.eth.getBlockNumber();
    try {
        console.log("Since block: ", staking.startBlock, "(Staking deployment)");
        console.log("Phoenix ATMX block deployment: ", phoenix.startBlock);
        console.log("Current block: ", curent_block);

        const retval = new Object();
        retval.staking = {};
        retval.staking.events_list = [];
        retval.staking.users = {};
        retval.users_to_handle = {}

        const staking_event_names = ["BindStake", "UnbindStake"];
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
        console.log(`INDEX, USER ADDRESS, PRINCIPAL STAKE [FET], UNCLAIMED REWARDS [ATMX], LAST CLAIMED AT BLOCK`);
        console.log(`----------------------------------------------------------------------------`);
        over_all = new BN("0");
        var i = 0;
        for (const [key, value] of Object.entries(retval.staking.users)) {
            await value.init();

            if (!value.principal.value.isZero() && value.phoenixDist.lastRewardBlock > 0) {
                value.rewards_to_claim = new BN(await phoenix.contract.methods.getAccumulatedRewards(value.address).call())
                over_all.iadd(value.rewards_to_claim);
                retval.users_to_handle[key] = value;

                console.log(`${i}, ${key}, ${canonicalFetToFet(value.principal.value)}, ${canonicalFetToFet(value.rewards_to_claim)}, ${value.phoenixDist.lastRewardBlock}`);
            }
            ++i;
        }

        console.log(`Over all unclaimed rewards so far: ${canonicalFetToFet(over_all)} ATMX`);

        console.log(`----------------------------------------------------------------------------`);

        console.log(`========================================`);
        console.log(`All relevant events for double-checking:`);
        const evts = retval.staking.events_list;
        for (let i = 0; i < evts.length; ++i) {
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
                } else if (e.event == "UnbindStake") {
                    console.log(`(-) {${e.returnValues.stakerAddress}}[claimed-at:${userDist.lastRewardBlock}][staked-at:${e.blockNumber}]: removed amount: ${canonicalFetToFet(e.returnValues.principal)} FET`);
                }
            }
            //console.log(`{${e.returnValues.stakerAddress}}@${e.event}[${e.blockNumber}]: ${canonicalFetToFet(e.returnValues.principal)}`);
        }
    }
    finally {
        web3.currentProvider.connection.close();
    }
}

main();
