// SPDX-License-Identifier:Apache-2.0
//------------------------------------------------------------------------------
//
//   Copyright 2020 Fetch.AI Limited
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.
//
//------------------------------------------------------------------------------

pragma solidity ^0.6.0;

import "../openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../openzeppelin/contracts/access/AccessControl.sol";
import "./Finance.sol";


// [Canonical ERC20-FET] = 10**(-18)x[ECR20-FET]
contract Staking is AccessControl {
    using SafeMath for uint256;
    using AssetLib for AssetLib.Asset;

    struct InterestRatePerBlock {
        uint256 sinceBlock;
        // NOTE(pb): To simplify, interest rate value can *not* be negative
        uint256 rate; // Signed interest rate in [10**18] units => real_rate = rate / 10**18.
        //// Number of users who bound stake while this particular interest rate was still in effect.
        //// This enables to identify when we can delete interest rates which are no more used by anyone
        //// (continuously from the beginning).
        //uint256 numberOfRegisteredUsers;
    }

    struct Stake {
        uint256 sinceBlock;
        uint256 sinceInterestRateIndex;
        AssetLib.Asset asset;
    }

    struct LockedAsset {
        uint256 liquidSinceBlock;
        AssetLib.Asset asset;
    }

    struct Locked {
        AssetLib.Asset aggregate;
        LockedAsset[] assets;
    }

    // *******    EVENTS    ********
    event BindStake(
          address indexed stakerAddress
        , uint256 indexed sinceInterestRateIndex
        , uint256 principal
        , uint256 compoundInterest
    );

    /**
     * @dev This event is triggered exclusivelly to recalculate the compount interest of ALREADY staked asset
     *      for the poriod since it was calculated the last time. This means this event does *NOT* include *YET*
     *      any added (resp. removed) asset user is currently binding (resp. unbinding).
     *      The main motivation for this event is to give listener opportunity to get feedback what is the 
     *      user's staked asset value with compound interrest recalculated to *CURRENT* block *BEFORE* user's
     *      action (binding resp. unbinding) affects user's staked asset value.
     */
    event StakeCompoundInterest(
          address indexed stakerAddress
        , uint256 indexed sinceInterestRateIndex
        , uint256 principal // = previous_principal
        , uint256 compoundInterest // = previous_principal * (pow(1+interest, _getBlockNumber()-since_block) - 1)
    );

    event LiquidityDeposited(
          address indexed stakerAddress
        , uint256 amount
    );

    event LiquidityUnlocked(
          address indexed stakerAddress
        , uint256 principal
        , uint256 compoundInterest
    );

    event UnbindStake(
          address indexed stakerAddress
        , uint256 indexed liquidSinceBlock
        , uint256 principal
        , uint256 compoundInterest
    );

    event NewInterestRate(
          uint256 indexed index
        , uint256 rate // Signed interest rate in [10**18] units => real_rate = rate / 10**18
    );

    event Withdraw(
          address indexed stakerAddress
        , uint256 principal
        , uint256 compoundInterest
    );

    event LockPeriod(uint64 numOfBlocks);
    event Pause(uint256 sinceBlock);
    event TokenWithdrawal(address targetAddress, uint256 amount);
    event ExcessTokenWithdrawal(address targetAddress, uint256 amount);
    event RewardsPoolTokenTopUp(address sender, uint256 amount);
    event RewardsPoolTokenWithdrawal(address targetAddress, uint256 amount);
    event DeleteContract();


    bytes32 public constant DELEGATE_ROLE = keccak256("DELEGATE_ROLE");
    uint256 public constant DELETE_PROTECTION_PERIOD = 370285;// 60*24*60*60[s] / (14[s/block]) = 370285[block];

    IERC20 public _token;

    // NOTE(pb): This needs to be either completely replaced by multisig concept,
    //           or at least joined with multisig.
    //           This contract does not have, by-design on conceptual level, any clearly defined repeating
    //           life-cycle behaviour (for instance: `initialise -> staking-period -> locked-period` cycle
    //           with clear start & end of each life-cycle. Life-cycle of this contract is single monolithic
    //           period `creation -> delete-contract`, where there is no clear place where to `update` the
    //           earliest deletion block value, thus it would need to be set once at the contract creation
    //           point what completely defeats the protection by time delay.
    uint256 public _earliestDelete;
    
    uint256 public _pausedSinceBlock;
    uint64 public _lockPeriodInBlocks;

    // Represents amount of reward funds which are dedicated to cover accrued compound interest during user withdrawals.
    uint256 public _rewardsPoolBalance;
    // Accumulated global value of all principals (from all users) currently held in this contract (liquid, bound and locked).
    uint256 public _accruedGlobalPrincipal;
    AssetLib.Asset public _accruedGlobalLiquidity; // Exact
    AssetLib.Asset public _accruedGlobalLocked; // Exact

    uint256 public _interestRatesStartIdx;
    uint256 public _interestRatesNextIdx;
    mapping(uint256 => InterestRatePerBlock) public _interestRates;

    mapping(address => Stake) _stakes;
    mapping(address => Locked) _locked;
    mapping(address => AssetLib.Asset) public _liquidity;


    /* Only callable by owner */
    modifier onlyOwner() {
        require(_isOwner(), "Caller is not an owner");
        _;
    }

    /* Only callable by owner or delegate */
    modifier onlyDelegate() {
        require(_isOwner() || hasRole(DELEGATE_ROLE, msg.sender), "Caller is neither owner nor delegate");
        _;
    }

    modifier verifyTxExpiration(uint256 expirationBlock) {
        require(_getBlockNumber() <= expirationBlock, "Transaction expired");
        _;
    }

    modifier verifyNotPaused() {
        require(_pausedSinceBlock > _getBlockNumber(), "Contract has been paused");
        _;
    }


    /*******************
    Contract start
    *******************/
    /**
     * @param ERC20Address address of the ERC20 contract
     */
    constructor(
          address ERC20Address
        , uint256 interestRatePerBlock
        , uint256 pausedSinceBlock
        , uint64  lockPeriodInBlocks) 
    public 
    {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _token = IERC20(ERC20Address);
        _earliestDelete = _getBlockNumber().add(DELETE_PROTECTION_PERIOD);
        
        // NOTE(pb): Unnecessary initialisations, shall be done implicitly by VM
        //_interestRatesStartIdx = 0;
        //_interestRatesNextIdx = 0;
        //_rewardsPoolBalance = 0;
        //_accruedGlobalPrincipal = 0;
        //_accruedGlobalLiquidity = 0;
        //_accruedGlobalLocked = 0;

        _updateLockPeriod(lockPeriodInBlocks);
        _addInterestRate(interestRatePerBlock);
        _pauseSince(pausedSinceBlock /* uint256(0) */);
    }


    /**
     * @notice Add new interest rate in to the ordered container of previously added interest rates
     * @param rate - signed interest rate value in [10**18] units => real_rate [1] = rate [10**18] / 10**18
     * @param expirationBlock - block number beyond which is the carrier Tx considered expired, and so rejected.
     *                     This is for protection of Tx sender to exactly define lifecycle length of the Tx,
     *                     and so avoiding uncertainty of how long Tx sender needs to wait for Tx processing.
     *                     Tx can be withheld
     * @dev expiration period
     */
    function addInterestRate(
        uint256 rate,
        uint256 expirationBlock
        )
        external
        onlyDelegate()
        verifyTxExpiration(expirationBlock)
    {
        _addInterestRate(rate);
    }


    function deposit(
        uint256 amount,
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused
    {
        bool makeTransfer = amount != 0;
        if (makeTransfer) {
            require(_token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
            _accruedGlobalPrincipal = _accruedGlobalPrincipal.add(amount);
            _accruedGlobalLiquidity.principal = _accruedGlobalLiquidity.principal.add(amount);
            emit LiquidityDeposited(msg.sender, amount);
        }

        uint256 curr_block = _getBlockNumber();
        (, AssetLib.Asset storage liquidity,) = _collectLiquidity(msg.sender, curr_block);

        if (makeTransfer) {
            liquidity.principal = liquidity.principal.add(amount);
       }
    }


    /**
     * @notice Withdraws amount from sender' available liquidity pool back to sender address,
     *         preferring withdrawal from compound interest dimension of liquidity.
     *
     * @param amount - value to withdraw
     *
     * @dev public access
     */
    function withdraw(
        uint256 amount,
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused
    {
        address sender = msg.sender;
        uint256 curr_block = _getBlockNumber();
        (, AssetLib.Asset storage liquidity,) = _collectLiquidity(sender, curr_block);

        AssetLib.Asset memory _amount = liquidity.iSubCompoundInterestFirst(amount);
        _finaliseWithdraw(sender, _amount, amount);
    }


    /**
     * @notice Withdraws *WHOLE* compound interest amount available to sender.
     *
     * @dev public access
     */
    function withdrawPrincipal(
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused
    {
        address sender = msg.sender;
        uint256 curr_block = _getBlockNumber();
        (, AssetLib.Asset storage liquidity, ) = _collectLiquidity(sender, curr_block);

        AssetLib.Asset memory _amount;
        _amount.principal = liquidity.principal;
        liquidity.principal = 0;

        _finaliseWithdraw(sender, _amount, _amount.principal);
    }


    /**
     * @notice Withdraws *WHOLE* compound interest amount available to sender.
     *
     * @dev public access
     */
    function withdrawCompoundInterest(
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused
    {
        address sender = msg.sender;
        uint256 curr_block = _getBlockNumber();
        (, AssetLib.Asset storage liquidity, ) = _collectLiquidity(sender, curr_block);

        AssetLib.Asset memory _amount;
        _amount.compoundInterest = liquidity.compoundInterest;
        liquidity.compoundInterest = 0;

        _finaliseWithdraw(sender, _amount, _amount.compoundInterest);
    }


    /**
     * @notice Withdraws whole liquidity available to sender back to sender' address,
     *
     * @dev public access
     */
    function withdrawWholeLiquidity(
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused
    {
        address sender = msg.sender;
        uint256 curr_block = _getBlockNumber();
        (, AssetLib.Asset storage liquidity, ) = _collectLiquidity(sender, curr_block);

        _finaliseWithdraw(sender, liquidity, liquidity.composite());
        liquidity.compoundInterest = 0;
        liquidity.principal = 0;
    }


    function bindStake(
        uint256 amount,
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused
    {
        require(amount != 0, "Amount must be higher than zero");

        uint256 curr_block = _getBlockNumber();

        (, AssetLib.Asset storage liquidity, ) = _collectLiquidity(msg.sender, curr_block);

        //// NOTE(pb): Strictly speaking, the following check is not necessary, since the requirement will be checked
        ////           during the `iRelocatePrincipalFirst(...)` method code flow (see bellow).
        //uint256 composite = liquidity.composite();
        //require(amount <= composite, "Insufficient liquidity.");

        Stake storage stake = _updateStakeCompoundInterest(msg.sender, curr_block);
        AssetLib.Asset memory _amount = liquidity.iRelocatePrincipalFirst(stake.asset, amount);
        _accruedGlobalLiquidity.iSub(_amount);

       //// NOTE(pb): Emitting only info about Tx input `amount` value, decomposed to principal & compound interest
       ////           coordinates based on liquidity available.
       //if (amount > 0) {
            emit BindStake(msg.sender, stake.sinceInterestRateIndex, _amount.principal, _amount.compoundInterest);
        //}
    }


    /**
     * @notice Unbinds amount from the stake of sender of the transaction,
     *         and *LOCKS* it for number of blocks defined by value of the
     *         `_lockPeriodInBlocks` state of this contract at the point
     *         of this call.
     *         The locked amount can *NOT* be withdrawn from the contract
     *         *BEFORE* the lock period ends.
     *
     *         Unbinding (=calling this method) also means, that compound
     *         interest will be calculated for period since la.
     *
     * @param amount - value to un-bind from the stake
     *                 If `amount=0` then the **WHOLE** stake (including
     *                 compound interest) will be unbound.
     *
     * @dev public access
     */
    function unbindStake(
        uint256 amount, //NOTE: If zero, then all stake is withdrawn
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused
    {
        uint256 curr_block = _getBlockNumber();
        address sender = msg.sender;
        Stake storage stake = _updateStakeCompoundInterest(sender, curr_block);

        uint256 stake_composite = stake.asset.composite();
        AssetLib.Asset memory _amount;

        if (amount > 0) {
            // TODO(pb): Failing this way is expensive (causing rollback of state change).
            //           It would be beneficial to retain newly calculated liquidity value
            //           in to the state, thus the invested calculation would not come to wain.
            //           However that comes with another implication - this would need
            //           to return status/error code instead of reverting = caller MUST actually
            //           check the return value, what might be trap for callers who do not expect
            //           this behaviour (Tx execution passed , but in fact the essential feature
            //           has not been fully executed).
            require(amount <= stake_composite, "Amount is higher than stake");

            if (_lockPeriodInBlocks == 0) {
                _amount = stake.asset.iRelocateCompoundInterestFirst(_liquidity[sender], amount);
                _accruedGlobalLiquidity.iAdd(_amount);
                emit UnbindStake(sender, curr_block, _amount.principal, _amount.compoundInterest);
                emit LiquidityUnlocked(sender, _amount.principal, _amount.compoundInterest);
            } else {
                Locked storage locked = _locked[sender];
                LockedAsset storage newLockedAsset = locked.assets.push();
                newLockedAsset.liquidSinceBlock = curr_block.add(_lockPeriodInBlocks);
                _amount = stake.asset.iRelocateCompoundInterestFirst(newLockedAsset.asset, amount);

                _accruedGlobalLocked.iAdd(_amount);
                locked.aggregate.iAdd(_amount);

                // NOTE: Emitting only info about Tx input values, not resulting compound values
                emit UnbindStake(sender, newLockedAsset.liquidSinceBlock, _amount.principal, _amount.compoundInterest);
            }
        } else {
            if (stake_composite == 0) {
                // NOTE(pb): Nothing to do
                return;
            }

            _amount = stake.asset;
            stake.asset.principal = 0;
            stake.asset.compoundInterest = 0;

            if (_lockPeriodInBlocks == 0) {
                _liquidity[sender].iAdd(_amount);
                _accruedGlobalLiquidity.iAdd(_amount);
                emit UnbindStake(sender, curr_block, _amount.principal, _amount.compoundInterest);
                emit LiquidityUnlocked(sender, _amount.principal, _amount.compoundInterest);
            } else {
                Locked storage locked = _locked[sender];
                LockedAsset storage newLockedAsset = locked.assets.push();
                newLockedAsset.liquidSinceBlock = curr_block.add(_lockPeriodInBlocks);
                newLockedAsset.asset = _amount;

                _accruedGlobalLocked.iAdd(_amount);
                locked.aggregate.iAdd(_amount);

                // NOTE: Emitting only info about Tx input values, not resulting compound values
                emit UnbindStake(msg.sender, newLockedAsset.liquidSinceBlock, newLockedAsset.asset.principal, newLockedAsset.asset.compoundInterest);
            }
        }
    }


    function getRewardsPoolBalance() external view returns(uint256) {
        return _rewardsPoolBalance;
    }


    function getEarliestDeleteBlock() external view returns(uint256) {
        return _earliestDelete;
    }


    function getNumberOfLockedAssetsForUser(address forAddress) external view returns(uint256 length) {
        length = _locked[forAddress].assets.length;
    }


    function getLockedAssetsAggregateForUser(address forAddress) external view returns(uint256 principal, uint256 compoundInterest) {
        AssetLib.Asset storage aggregate = _locked[forAddress].aggregate;
        return (aggregate.principal, aggregate.compoundInterest);
    }


    /**
     * @dev Returns locked assets decomposed in to 3 separate arrays (principal, compound interest, liquid since block)
     *      NOTE(pb): This method might be quite expensive, depending on size of locked assets
     */
    function getLockedAssetsForUser(address forAddress)
        external view
        returns(uint256[] memory principal, uint256[] memory compoundInterest, uint256[] memory liquidSinceBlock)
    {
        LockedAsset[] storage lockedAssets = _locked[forAddress].assets;
        uint256 length = lockedAssets.length;
        if (length != 0) {
            principal = new uint256[](length);
            compoundInterest = new uint256[](length);
            liquidSinceBlock = new uint256[](length);

            for (uint256 i=0; i < length; ++i) {
                LockedAsset storage la = lockedAssets[i];
                AssetLib.Asset storage a = la.asset;
                principal[i] = a.principal;
                compoundInterest[i] = a.compoundInterest;
                liquidSinceBlock[i] = la.liquidSinceBlock;
            }
        }
    }


    function getStakeForUser(address forAddress) external view returns(uint256 principal, uint256 compoundInterest, uint256 sinceBlock, uint256 sinceInterestRateIndex) {
        Stake storage stake = _stakes[forAddress];
        principal = stake.asset.principal;
        compoundInterest = stake.asset.compoundInterest;
        sinceBlock = stake.sinceBlock;
        sinceInterestRateIndex = stake.sinceInterestRateIndex;
    }


    /**
       @dev Even though this is considered as administrative action (is not affected by
            by contract paused state, it can be executed by anyone who wishes to
            top-up the rewards pool (funds are sent in to contract, *not* the other way around).
            The Rewards Pool is exclusively dedicated to cover withdrawals of user' compound interest,
            which is effectively the reward.
     */
    function topUpRewardsPool(
        uint256 amount,
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
    {
        if (amount == 0) {
            return;
        }

        require(_token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        _rewardsPoolBalance = _rewardsPoolBalance.add(amount);
        emit RewardsPoolTokenTopUp(msg.sender, amount);
    }


    /**
     * @notice Updates Lock Period value
     * @param numOfBlocks  length of the lock period
     * @dev Delegate only
     */
    function updateLockPeriod(uint64 numOfBlocks, uint256 txExpirationBlock)
        external
        verifyTxExpiration(txExpirationBlock)
        onlyDelegate
    {
        _updateLockPeriod(numOfBlocks);
    }


    /**
     * @notice Pauses all NON-administrative interaction with the contract since the specidfed block number 
     * @param blockNumber block number since which non-admin interaction will be paused (for all _getBlockNumber() >= blockNumber)
     * @dev Delegate only
     */
    function pauseSince(uint256 blockNumber, uint256 txExpirationBlock)
        external
        verifyTxExpiration(txExpirationBlock)
        onlyDelegate
    {
        _pauseSince(blockNumber);
    }


    /**
     * @dev Withdraw tokens from rewards pool.
     *
     * @param amount : amount to withdraw.
     *                 If `amount == 0` then whole amount in rewards pool will be withdrawn.
     * @param targetAddress : address to send tokens to
     */
    function withdrawFromRewardsPool(uint256 amount, address payable targetAddress,
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        onlyOwner
    {
        if (amount == 0) {
            amount = _rewardsPoolBalance;
        } else {
            require(amount <= _rewardsPoolBalance, "Amount higher than rewards pool");
        }

        // NOTE(pb): Strictly speaking, consistency check in following lines is not necessary,
        //           the if-else code above guarantees that everything is alright:
        uint256 contractBalance = _token.balanceOf(address(this));
        uint256 expectedMinContractBalance = _accruedGlobalPrincipal.add(amount);
        require(expectedMinContractBalance <= contractBalance, "Contract inconsistency.");

        require(_token.transfer(targetAddress, amount), "Not enough funds on contr. addr.");

        // NOTE(pb): No need for SafeMath.sub since the overflow is checked in the if-else code above.
        _rewardsPoolBalance -= amount;

        emit RewardsPoolTokenWithdrawal(targetAddress, amount);
    }


    /**
     * @dev Withdraw "excess" tokens, which were sent to contract directly via direct ERC20.transfer(...),
     *      without interacting with API of this (Staking) contract, what could be done only by mistake.
     *      Thus this method is meant to be used primarily for rescue purposes, enabling withdrawal of such
     *      "excess" tokens out of contract.
     * @param targetAddress : address to send tokens to
     * @param txExpirationBlock : block number until which is the transaction valid (inclusive).
     *                            When transaction is processed after this block, it fails.
     */
    function withdrawExcessTokens(address payable targetAddress, uint256 txExpirationBlock)
        external
        verifyTxExpiration(txExpirationBlock)
        onlyOwner
    {
        uint256 contractBalance = _token.balanceOf(address(this));
        uint256 expectedMinContractBalance = _accruedGlobalPrincipal.add(_rewardsPoolBalance);
        // NOTE(pb): The following subtraction shall *fail* (revert) IF the contract is in *INCONSISTENT* state,
        //           = when contract balance is less than minial expected balance:
        uint256 excessAmount = contractBalance.sub(expectedMinContractBalance);
        require(_token.transfer(targetAddress, excessAmount), "Not enough funds on contr. addr.");
        emit ExcessTokenWithdrawal(targetAddress, excessAmount);
    }


    /**
     * @notice Delete the contract, transfers the remaining token and ether balance to the specified
       payoutAddress
     * @param payoutAddress address to transfer the balances to. Ensure that this is able to handle ERC20 tokens
     * @dev owner only + only on or after `_earliestDelete` block
     */
    function deleteContract(address payable payoutAddress, uint256 txExpirationBlock)
    external
    verifyTxExpiration(txExpirationBlock)
    onlyOwner
    {
        require(_earliestDelete >= _getBlockNumber(), "Earliest delete not reached");
        uint256 contractBalance = _token.balanceOf(address(this));
        require(_token.transfer(payoutAddress, contractBalance));
        emit DeleteContract();
        selfdestruct(payoutAddress);
    }
 

    // **********************************************************
    // ******************    INTERNAL METHODS   *****************


    /**
     * @dev VIRTUAL Method returning bock number. Introduced for 
     *      testing purposes (allows mocking).
     */
    function _getBlockNumber() internal view virtual returns(uint256)
    {
        return block.number;
    }


    function _isOwner() internal view returns(bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }


    /**
     * @notice Add new interest rate in to the ordered container of previously added interest rates
     * @param rate - signed interest rate value in [10**18] units => real_rate [1] = rate [10**18] / 10**18
     */
    function _addInterestRate(uint256 rate) internal 
    {
        uint256 idx = _interestRatesNextIdx;
        _interestRates[idx] = InterestRatePerBlock({
              sinceBlock: _getBlockNumber()
            , rate: rate
            //,numberOfRegisteredUsers: 0
            });
        _interestRatesNextIdx = _interestRatesNextIdx.add(1);

        emit NewInterestRate(idx, rate);
    }


    /**
     * @notice Updates Lock Period value
     * @param numOfBlocks  length of the lock period
     */
    function _updateLockPeriod(uint64 numOfBlocks) internal
    {
        _lockPeriodInBlocks = numOfBlocks;
        emit LockPeriod(numOfBlocks);
    }


    /**
     * @notice Pauses all NON-administrative interaction with the contract since the specidfed block number 
     * @param blockNumber block number since which non-admin interaction will be paused (for all _getBlockNumber() >= blockNumber)
     */
    function _pauseSince(uint256 blockNumber) internal 
    {
        uint256 currentBlockNumber = _getBlockNumber();
        _pausedSinceBlock = blockNumber < currentBlockNumber ? currentBlockNumber : blockNumber;
        emit Pause(_pausedSinceBlock);
    }


    /**
     * @notice Withdraws amount from sender' available liquidity pool back to sender address,
     *         preferring withdrawal from compound interest dimension of liquidity.
     *
     * @param amount - value to withdraw
     *
     * @dev NOTE(pb): Passing redundant `uint256 amount` (on top of the `Asset _amount`) in the name
     *                of performance to avoid calculating it again from `_amount` (or the other way around).
     *                IMPLICATION: Caller **MUST** pass correct values, ensuring that `amount == _amount.composite()`,
     *                since this private method is **NOT** verifying this condition due to performance reasons.
     */
    function _finaliseWithdraw(address sender, AssetLib.Asset memory _amount, uint256 amount) internal {
         if (amount != 0) {
            require(_rewardsPoolBalance >= _amount.compoundInterest, "Not enough funds in rewards pool");
            require(_token.transfer(sender, amount), "Transfer failed");

            _rewardsPoolBalance = _rewardsPoolBalance.sub(_amount.compoundInterest);
            _accruedGlobalPrincipal = _accruedGlobalPrincipal.sub(_amount.principal);
            _accruedGlobalLiquidity.iSub(_amount);

            // NOTE(pb): Emitting only info about Tx input `amount` value, decomposed to principal & compound interest
            //           coordinates based on liquidity available.
            emit Withdraw(msg.sender, _amount.principal, _amount.compoundInterest);
         }
    }


    function _updateStakeCompoundInterest(address sender, uint256 at_block)
        internal
        returns(Stake storage stake)
    {
        stake = _stakes[sender];
        uint256 composite = stake.asset.composite();
        if (composite != 0)
        {
            // TODO(pb): There is more effective algorithm than this.
            uint256 start_block = stake.sinceBlock;
            // NOTE(pb): Probability of `++i`  or `j=i+1` overflowing is limitly approaching zero,
            // since we would need to create `(1<<256)-1`, resp `1<<256)-2`,  number of interrest rates in order to reach the overflow
            for (uint256 i=stake.sinceInterestRateIndex; i < _interestRatesNextIdx; ++i) {
                InterestRatePerBlock storage interest = _interestRates[i];
                // TODO(pb): It is not strictly necessary to do this assert, and rather fully rely
                //           on correctness of `addInterestRate(...)` implementation.
                require(interest.sinceBlock <= start_block, "sinceBlock inconsistency");
                uint256 end_block = at_block;

                uint256 j = i + 1;
                if (j < _interestRatesNextIdx) {
                    InterestRatePerBlock storage next_interest = _interestRates[j];
                    end_block = next_interest.sinceBlock;
                }

                composite = Finance.compoundInterest(composite, interest.rate, end_block - start_block);
                start_block = end_block;
            }

            stake.asset.compoundInterest = composite.sub(stake.asset.principal);
        }

        stake.sinceBlock = at_block;
        stake.sinceInterestRateIndex = (_interestRatesNextIdx != 0 ? _interestRatesNextIdx - 1 : 0);
        // TODO(pb): Careful: The `StakeCompoundInterest` event doers not carry explicit block number value - it relies
        //           on the fact that Event implicitly carries value block.number where the event has been triggered,
        //           what however can be different than value of the `at_block` input parameter passed in.
        //           Thus this method needs to be EITHER refactored to drop the `at_block` parameter (and so get the
        //           value internally by calling the `_getBlockNumber()` method), OR the `StakeCompoundInterest` event
        //           needs to be extended to include the `uint256 sinceBlock` attribute.
        //           The original reason for passing the `at_block` parameter was to spare gas for calling the
        //           `_getBlockNumber()` method twice (by the caller of this method + by this method), what might NOT be
        //           relevant anymore (after refactoring), since caller might not need to use the block number value anymore.
        emit StakeCompoundInterest(sender, stake.sinceInterestRateIndex, stake.asset.principal, stake.asset.compoundInterest);
    }


    function _collectLiquidity(address sender, uint256 at_block)
        internal
        returns(AssetLib.Asset memory unlockedLiquidity, AssetLib.Asset storage liquidity, bool collected)
    {
        Locked storage locked = _locked[sender];
        LockedAsset[] storage lockedAssets = locked.assets;
        liquidity = _liquidity[sender];

        for (uint256 i=0; i < lockedAssets.length; ) {
            LockedAsset memory l = lockedAssets[i];

            if (l.liquidSinceBlock > at_block) {
                ++i; // NOTE(pb): Probability of overflow is zero, what is ensured by condition in this for cycle.
                continue;
            }

            unlockedLiquidity.principal = unlockedLiquidity.principal.add(l.asset.principal);
            // NOTE(pb): The following can potentially overflow, since accrued compound interest can be high, depending on values on sequence of interest rates & length of compounding intervals involved.
            unlockedLiquidity.compoundInterest = unlockedLiquidity.compoundInterest.add(l.asset.compoundInterest);

            // Copying last element of the array in to the current one,
            // so that the last one can be popped out of the array.
            // NOTE(pb): Probability of overflow during `-` operation is zero, what is ensured by condition in this for cycle.
            uint256 last_idx = lockedAssets.length - 1;
            if (i != last_idx) {
                lockedAssets[i] = lockedAssets[last_idx];
            }
            // TODO(pb): It will be cheaper (GAS consumption-wise) to simply leave
            // elements in array (do NOT delete them) and rather store "amortised"
            // size of the array in secondary separate store variable (= do NOT
            // use `array.length` as primary indication of array length).
            // Destruction of the array items is expensive. Excess of "allocated"
            // array storage can be left temporarily (or even permanently) unused.
            lockedAssets.pop();
        }

        // TODO(pb): This should not be necessary.
        if (lockedAssets.length == 0) {
            delete _locked[sender];
        }

        collected = unlockedLiquidity.principal != 0 || unlockedLiquidity.compoundInterest != 0;
        if (collected) {
             emit LiquidityUnlocked(sender, unlockedLiquidity.principal, unlockedLiquidity.compoundInterest);

            _accruedGlobalLocked.iSub(unlockedLiquidity);
            if (lockedAssets.length != 0) {
                locked.aggregate.iSub(unlockedLiquidity);
            }

            _accruedGlobalLiquidity.iAdd(unlockedLiquidity);

            liquidity.iAdd(unlockedLiquidity);
        }
    }

}
