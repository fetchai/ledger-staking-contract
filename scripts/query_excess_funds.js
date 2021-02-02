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

const abi_IERC20 = require(path.join(dir, 'IERC20.json')).abi;
const token_contract_address = "0xaea46A60368A7bD060eec7DF8CBa43b7EF41Ad85";
//const token_contract_deployment_block = "10998076";

const abi_Staking = require(path.join(dir,'Staking.json')).abi;
const staking_contract_address = "0x351baC612B50e87B46e4b10A282f632D41397DE2";
const staking_contract_deployment_block = "11061460";

const infuraProjectId = fs.readFileSync(path.join(home_dir, '.secrets_infura_project_id')).toString().trim();
const _endpoint = 'wss://mainnet.infura.io/ws/v3';
let endpoint = `${_endpoint}/${infuraProjectId}`;

const web3 = new Web3(endpoint);
const token = new web3.eth.Contract(abi_IERC20, token_contract_address);
const staking = new web3.eth.Contract(abi_Staking, staking_contract_address);


async function main () {
    const curent_block = await web3.eth.getBlockNumber();
    console.log("Current block: ", curent_block);

    const retval = {}
    await token.getPastEvents("Transfer", {
        filter: {to: staking_contract_address},
        fromBlock: staking_contract_deployment_block,
        toBlock: "latest",
    }, (error, events) => {
        if (error) {
            console.log("error: ", error);
            throw error;
        }
        retval.erc20 = {};
        retval.erc20.events_list = events;
    });

    retval.staking = {};
    retval.staking.events_list = [];
    retval.staking.events_dict = {};

    const staking_event_names = ["LiquidityDeposited", "RewardsPoolTokenTopUp"];
    for (let i = 0; i<staking_event_names.length; ++i) {
        const evt_name = staking_event_names[i];
        await staking.getPastEvents(evt_name, {
            fromBlock: staking_contract_deployment_block,
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
                    if (e.transactionHash in evts_dict) {
                        evts_dict[e.transactionHash].push(e);
                    } else {
                        evts_dict[e.transactionHash] = [e];
                    }
                }
            });
    }

    const aggregate = new BN("0");

    const events = retval.erc20.events_list;
    const staking_evts_dict = retval.staking.events_dict;
    const excess_funds_events_list = [];
    retval.exces_funds_events_list = excess_funds_events_list;

    for (let i=0; i< events.length; ++i) {
        const e = events[i];
        if (! (e.transactionHash in staking_evts_dict)) {
            excess_funds_events_list.push(e);
            const transfer_amount = new BN(e.returnValues.value);
            console.log(`[${excess_funds_events_list.length - 1}] ${e.returnValues.from} : `, canonicalFetToFet(transfer_amount).toString(), "[FET] =", transfer_amount.toString(), `[Canonical FET], {https://etherscan.io/tx/${e.transactionHash}}`);
            aggregate.iadd(transfer_amount);
        }
    }

    dumpToJsonFile(`${dir}/events.json`, retval, null, "  ");

    const principal = new BN(await staking.methods._accruedGlobalPrincipal().call());
    const rewards_pool_balance = new BN(await staking.methods.getRewardsPoolBalance().call());
    const balance = new BN(await token.methods.balanceOf(staking_contract_address).call());
    const expected_excess_funds_amount = balance.sub(principal.add(rewards_pool_balance));
    const expected_excess_funds_amount_dec = canonicalFetToFet(expected_excess_funds_amount);
    const aggregateDec = canonicalFetToFet(aggregate);

    console.log("Number of excess transfer events:", excess_funds_events_list.length);
    console.log("Aggregated value:", aggregateDec.toString(), "[FET] =", aggregate.toString(), "[Canonical FET]");

    if (aggregate.eq(expected_excess_funds_amount)) {
        console.log("SUCCESS: calculated aggregate equals to expected value.");
    } else {
        console.log("Expected value  :", expected_excess_funds_amount_dec.toString(), "[FET] =", expected_excess_funds_amount.toString(), "[Canonical FET]");
        console.log("FAILURE: calculated aggregate and expected value DIFFER!");
    }

    web3.currentProvider.connection.close();
}

main();
