# How to Verify & Publish Contract Source Code on Etherscan.io

## 1: Prerequisities: Installing OpenZeppelin contracts v3.0.0
We need to have access to OpenZeppelin contracts since our contracts use them as dependency.

<br/>

### 1.1: EITHER Install them from GitHub (recommended)
One way would be to get them is to clone OpeZeppelin v3.0.0 GitHub repository to your local machine
```console
#####  We assume here that we are *IN* the folder where `mettalex-token` gihub repository is already cloned in to  ####
git clone --branch v3.0.0 --depth 1 https://github.com/OpenZeppelin/openzeppelin-contracts.git openzeppelin
```
> !!! Please keep in mind, that **IF** you have done this, then you do **NOT** need to install the `brownie` tool and do the steps described in the ["1.2: OR Install them via the `brownie` tooll" section](#1.2:-or-install-them-via-the-brownie-tool) bellow !!!

<br/>

### 1.2: OR Install them via the `brownie` tool
Another way to install OpenZeppelin contracts is using `brownie` tool, which is actually the tool selected in this repository for handling contract deployment activities like compilation, deployment, etc. ...

First we need to install the tool itself - see the [it's github repo](https://github.com/eth-brownie/brownie) for the instructions.

Then we need to install OpenZeppelin contracts via brownie tool as it's package:
```console
brownie pm install OpenZeppelin/openzeppelin-contracts@3.0.0
```

That will place the OpenZeppelin contracts in to the `~/.brownie/packages/OpenZeppelin/openzeppelin-contracts\@3.0.0` directory.

Then it is necessary expose the installed contracts in to the `mettalex-token`, easiest way to do that is via symbolic-link:
```console
ln -s ~/.brownie/packages/OpenZeppelin/openzeppelin-contracts\@3.0.0 openzeppelin
```
> NOTE: This is necessary primarily for solidity flattener tool (described in sections bellow), which is unable to deal with absolute paths provided for solidity imports re-mappings on its command-line). But it also simplifies things for `solc` compiler when run manually. 

<br/>
<br/>

## 2: Verify & Publish Contract Source on Etherescan.io

<br/>

### 2.1: Using "Solidity (Single file)" option
This is the easiest way how to verify & publish the contract which has dependencies.

Install the [Solidity Flattener](https://github.com/bokkypoobah/SolidityFlattener) tool from GitHub. Easiest way how to do that is simply clone it's github repo in to the `mettalex-token` repo folder:
```console
#####  We assume here that we are *IN* the folder where `mettalex-token` gihub repository is already cloned in to  ####
git clone --branch v1.0.2 --depth 1 https://github.com/bokkypoobah/SolidityFlattener
```

> Please note that this solidity flattener tool needs to have `perl` interpreter installed. On most linux based systems it is very reasonable assumption that perl is already installed.

Then, finally, create the flattened version of the contract source code which you want to verify & publish, in this case of the `Staking.sol` contract:
```console
#####  We assume here that we are *IN* the folder where `mettalex-token` gihub repository is already cloned in to  ####
SolidityFlattener/solidityFlattener.pl --contractsdir=contracts --remapdir "@openzeppelin/=../openzeppelin/" --mainsol=Staking.sol --verbose --outputsol published_contracts/Staking.sol_0x7354f36fd74a656b4db8429c3fd937b99cd69e45/Staking_flattened.sol
```
The above command stores the resulting flattened version of the original `Staking.sol` contract in to `Staking_flattened.sol` file located in the `published_contracts/Staking.sol_0x7354f36fd74a656b4db8429c3fd937b99cd69e45/` folder.

Content of the generated flattened file needs to be copy-pasted (as is) in to edit box provided in Etherscan.io .

<br/>

### 2.2: Using "Solidity (Standard-Json-Input)" option

This requires to create the [Standard Json-Input](https://solidity.readthedocs.io/en/v0.5.7/using-the-compiler.html#compiler-input-and-output-json-description) configuration file for `solc` compiler.

The standard json input file contains everything necessary for `solc` compiler to compile the contract(s) - all compilation options & configuration including whole source code of contract(s) co compile, what means that this single file contains everything necessary to perform the compilation.

<br/>

#### 2.2.1: EITHER Use the `brownie` tool:
One way how to generate it is to use `brownie` tool using the ` compiler.generate_input_json(...)` (see the [documentation](https://eth-brownie.readthedocs.io/en/latest/api-project.html?highlight=json#compiler.generate_input_json)).

> NOTE: I have not tried this yet, so I can not guarantee it will work as expected generating standard input json file as required by Etherscan.io .

<br/>

#### 2.2.2: OR Do it manually:
Another way would be is to create it by hand based on the Standard Json-Input documentation (see link above).
The  `solc` command can help here a little bit - it is able to generate all-in-one output json file using `--combined-json` option together with all necessary compilation options on it's commandline, see the example bellow:
```console
solc @openzeppelin/=./openzeppelin/ --combined-json "abi,asm,ast,bin,bin-runtime,compact-format,devdoc,hashes,interface,metadata,opcodes,srcmap,srcmap-runtime,userdoc" --overwrite --optimize --optimize-runs 200 --allow-paths . -o ./ contracts/Staking.sol
```
This command will create output json file with name `combined.json` in the current working directory as defined by  `-o ./` option.

This output json file has a little bit different structure than standard INPUT json we need, but it contains all what is necessary - specifically in it's `"metadata"` elements.

There is one `"metadata"` element per each contract which was required for the compilation, what obviously includes all dependencies (= all imported contracts).

However, the standard input json file still needs to be created manually (at least at this point) as it has a little bit different format than output json file. It is necessary to locate all "metadata" elements in the `combined.json` file, dissect their content and put it in to the created standard input json file in the right place + perhaps modify a few bits & pieces as necessary based on standard input json documentation.

> NOTE: Perhaps in the future  there will be the tool which will automate this process.

