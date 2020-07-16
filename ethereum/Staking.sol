pragma solidity ^0.6.0;

import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
//import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/access/AccessControl.sol";
//import "./openzeppelin/contracts/utils/Pausable.sol";
import "./abdk-libraries/ABDKMath64x64.sol";
import "./Finance.sol";



// [Canonical ERC20-FET] = 10**(-18)x[ECR20-FET]
contract Staking is AccessControl {
    using SafeMath for uint256;

    struct InterestRatePerBlock {
        uint256 sinceBlock;
        int256  rate; // Signed interest rate in [10**18] units => real_rate = rate / 10**18
    }

    struct Stake {
        uint256 sinceBlock;
        uint64  sinceInterestRateIndex;
        uint256 amount; // [Canonical ERC20-FET]
    }

    struct  Liquidity {
        uint256 liquidSinceBlock;
        uint256 amount; // [Canonical ERC20-FET]
    }



    event BindStake(
          address indexed stakerAddress
        , uint256 indexed sinceBlock
        , uint64 indexed sinceInterestRateIndex
        , uint256 stakedAmount
        //// NOTE(pb): Following commented-out event members are not strictly necessary,
        ////           since they can be derived by event listener from members above assuming
        ////           that listener received all historical events.
        ////           Also, the compound_interest value might be complex to calculate, since
        ////           it might be negative in general (in highly unlikely scenario of *negative*
        ////           interest rate), where we would need to cast unsigned to signed integer
        ////           what comes with consequences of deal with overflow.
        //, uint256 principal // = previous_principal + addedStake
        // NOTE(pb): In general, the compound interest could be negative if at least some of interest rates are negative.
        //, int256 compoundInterest // = previous_principal * (pow(1+interest, block.number-since_block) - 1)
    );

    event LiquidityInjected(
          address indexed stakerAddress
        , uint256 amount
    );

    event LiquidityUnlocked(
          address indexed stakerAddress
        , uint256 amount
    );

    event UnbindStake(
          address indexed stakerAddress
        , uint256 indexed liquidSinceBlock
        , uint256 amount
    );

    event NewInterestRate(
          uint128 indexed index
        , int256 rate // Signed interest rate in [10**18] units => real_rate = rate / 10**18
    );

    event Withdraw(
          address indexed stakerAddress
        , uint256 amount
    );

    event LockPeriod(uint64 num_of_blocks);
    event Pause(uint256 sinceBlock);
    event TokenWithdrawal(address targetAddress, uint256 amount);
    event DeleteContract();


    bytes32 public constant DELEGATE_ROLE = keccak256("DELEGATE_ROLE");


    ERC20 public _token;
    uint256 public _pausedSinceBlock;
    uint64 public _lockPeriodInBlocks;
    uint64 public _interestRatesStartIdx;
    uint64 public _interestRatesNextIdx;
    // interest rate random access index => InterestRatePerBlock
    mapping(uint64 => InterestRatePerBlock) public _interestRates;
    mapping(address => Stake) public _stakes;
    mapping(address => Liquidity[]) public _liquidity;


    function _isOwner() internal view returns(bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

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
        require(block.number <= expirationBlock, "Transaction expired");
        _;
    }

    modifier verifyNotPaused() {
        require(_pausedSinceBlock > block.number, "Contract has been paused");
        _;
    }


    /*******************
    Contract start
    *******************/
    /**
     * @param ERC20Address address of the ERC20 contract
     */
    constructor(address ERC20Address) public {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _token = ERC20(ERC20Address);
        _lockPeriodInBlocks = 185142; // = 30*24*60*60[s] / (14[s/block]);
        _interestRatesStartIdx = 0;
        _interestRatesNextIdx = 0;
        _pausedSinceBlock = uint256(1)<<255;
    }

    /**
     * @notice Add new interest rate in to the ordered container of previously added interest rates
     * @param rate - signed interest rate value in [10**18] units => real_rate = rate / 10**18
     * @ expirationBlock - block number beyond which is the carrier Tx considered expired, and so rejected.this
     *                     This is for protection of Tx sender to exactly define lifecycle length of the Tx,
     *                     and so avoiding uncertainty of how long Tx sender needs to wait for Tx processing.
     * @dev expiration period
     */
    function addInterestRate(
        int256 rate,
        uint256 expirationBlock
        )
        external
        onlyDelegate()
        verifyTxExpiration(expirationBlock)
    {
        uint64 idx = _interestRatesNextIdx;
        _interestRates[idx] = InterestRatePerBlock({
            sinceBlock: block.number,
            rate: rate});
        _interestRatesNextIdx += 1;

        emit NewInterestRate(idx, rate);
    }


    function addLiquidity(
        uint256 amount,
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused()
    {
        uint256 curr_block = block.number;
        Liquidity[] storage sender_lqdts = _liquidity[msg.sender];

        uint256 amount_unlocked = _collectLiquidity(sender_lqdts, curr_block);

        bool make_transfer = amount > 0;
        if (make_transfer) {
            require(_token.transferFrom(msg.sender, address(this), amount));
        }

        if (make_transfer || amount_unlocked > 0) {
            sender_lqdts.push(Liquidity({
                liquidSinceBlock: curr_block,
                amount: amount.add(amount_unlocked)
                }));
        }
        // TODO(pb): This should not be necessary.
        if (sender_lqdts.length == 0)
        {
            delete _liquidity[msg.sender];
        }

        emit LiquidityInjected(msg.sender, amount);
        emit LiquidityUnlocked(msg.sender, amount_unlocked);
    }


    function bindStake(
        uint256 amount,
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused()
    {
        require(amount > 0, "Amount must be higher than zero");

        uint256 curr_block = block.number;
        Liquidity[] storage sender_lqdts = _liquidity[msg.sender];
        uint256 amount_unlocked = _collectLiquidity(sender_lqdts, curr_block);
        require(amount <= amount_unlocked, "Insufficient liquidity.");

        uint256 remaining_liquidity = amount_unlocked.sub(amount);

        if (remaining_liquidity > 0) {
            sender_lqdts.push(Liquidity({
                amount: remaining_liquidity,
                liquidSinceBlock: curr_block
                }));
        }

        // TODO(pb): This should not be necessary.
        if (sender_lqdts.length == 0)
        {
            delete _liquidity[msg.sender];
        }

        Stake storage stake = _stakes[msg.sender];
        uint256 principal = _calculateNewPrincipal(stake);

        //var previous_principal = stake.amount;
        //var new_principal = previous_principal.add(amount);
        //// NOTE(pb): In general, the compound interest could be negative if at least some of interest rates are negative.
        //int256 compound_interest = 0;
        //if (principal > previous_principal) {
        //    var compound_inter = principal.sub(previous_principal);
        //}
        //else {
        //    var negative_compound_inter = previous_principal.sub(principal);
        //}

        stake.amount = principal.add(amount);
        // NOTE: The current block is not counted/included in to compound interest calculation:
        stake.sinceBlock = curr_block;
        stake.sinceInterestRateIndex = (_interestRatesNextIdx > 0 ? _interestRatesNextIdx - 1 : 0);

        // NOTE: Emitting only info about Tx input values, not resulting compound values
        emit BindStake(msg.sender, curr_block, stake.sinceInterestRateIndex, amount/*, new_principal, principal - previous_principal*/);
        if (remaining_liquidity > 0) {
            emit LiquidityUnlocked(msg.sender, remaining_liquidity);
        }
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
     *         interest will be calculated for period.
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
        verifyNotPaused()
    {
        uint256 curr_block = block.number;
        Stake memory stake = _stakes[msg.sender];

        uint256 new_principal = _calculateNewPrincipal(stake);
        uint256 remaining_principal = 0;
        uint256 amount_to_unbind = new_principal;

        if (amount > 0) {
            // TODO(pb): Failing this way is expensive (causing rollback of state change).
            //           It would be beneficial to retain newly calculated liquidity value
            //           in to the state, thus the invested calculation would not come to wain.
            //           However that would comes with another implication - this would need
            //           to return status/error code instead of failing = caller MUST actually
            //           check the return value, what might be trap for callers who do not expect
            //           this behaviour (passed Tx execution when in fact the essential feature
            //           has not been fully executed).
            require(amount <= new_principal, "Amount is higher than stake");
            amount_to_unbind = amount;
            remaining_principal = new_principal.sub(amount);
        }

        if (remaining_principal > 0) {
            Stake storage stake_stor = _stakes[msg.sender];
            stake_stor.amount = remaining_principal;
            // NOTE: The current block is not counted/included in to compound interest calculation:
            stake_stor.sinceBlock = curr_block;
            stake_stor.sinceInterestRateIndex = (_interestRatesNextIdx > 0 ? _interestRatesNextIdx - 1 : 0);
        }
        else {
            delete _stakes[msg.sender];
        }


        Liquidity[] storage sender_lqdts = _liquidity[msg.sender];
        uint256 amount_unlocked = _collectLiquidity(sender_lqdts, curr_block);

        if (amount_to_unbind > 0) {
            sender_lqdts.push(Liquidity({
                amount: amount_to_unbind,
                liquidSinceBlock: curr_block.add(_lockPeriodInBlocks)
                }));
        }

        if (amount_unlocked > 0) {
            sender_lqdts.push(Liquidity({
                amount: amount_unlocked,
                liquidSinceBlock: curr_block
                }));
        }

        // TODO(pb): This should not be necessary.
        if (sender_lqdts.length == 0)
        {
            // TODO(pb): Not quite sure this will work properly since we have live storage
            //           reference `sender_lqdts` present in this scope. It is reference to
            //           to the array item of the owning maping state container, and we are
            //           trying to delete that very item from the owning mapping container.
            delete _liquidity[msg.sender];
        }

        // NOTE: Emitting only info about Tx input values, not resulting compound values
        emit UnbindStake(msg.sender, curr_block, amount_to_unbind);

        if (amount_unlocked > 0) {
            emit LiquidityUnlocked(msg.sender, amount_unlocked);
        }
    }


    /**
     * @notice Withdraws amount from sender' accessible(=unlocked) liquidity pool
     *         back to sender address.
     *
     * @param amount - value to withdraw
     *                 If `amount=0` then **WHOLE** accessible(=unlocked) liquidity
     *                 (at the point of this call) will be withdrawn.
     *
     * @dev public access
     */
    function withdraw(
        uint256 amount, //NOTE: If zero, then all liquidity available is withdrawn
        uint256 txExpirationBlock
        )
        external
        verifyTxExpiration(txExpirationBlock)
        verifyNotPaused()
    {
        uint256 curr_block = block.number;
        Liquidity[] storage sender_lqdts = _liquidity[msg.sender];
        uint256 unlocked_liquidity = _collectLiquidity(sender_lqdts, curr_block);
        uint256 remaining_unlocked_liquidity = 0;
        uint256 amount_to_transfer = unlocked_liquidity;

        if (amount > 0) {
            // TODO(pb): Failing this way is expensive (causing rollback of state change).
            //           It would be beneficial to retain newly calculated liquidity value
            //           in to the state, thus the invested calculation would not come to wain.
            //           However that would comes with another implication - this would need
            //           to return status/error code instead of failing = caller MUST actually
            //           check the return value, what might be trap for callers who do not expect
            //           this behaviour (passed Tx execution when in fact the essential feature
            //           has not been fully executed).
            require(amount <= unlocked_liquidity, "Amount is higher than liquidity");
            amount_to_transfer = amount;
            remaining_unlocked_liquidity = unlocked_liquidity.sub(amount);
        }

        if (amount_to_transfer > 0) {
            require(_token.transfer(msg.sender, amount_to_transfer), "Transfer failed");
        }

        if (remaining_unlocked_liquidity > 0) {
            sender_lqdts.push(Liquidity({
                amount: remaining_unlocked_liquidity,
                liquidSinceBlock: curr_block
                }));
        }

        // TODO(pb): This should not be necessary.
        if (sender_lqdts.length == 0)
        {
            delete _liquidity[msg.sender];
        }

        if (amount_to_transfer > 0) {
            emit Withdraw(msg.sender, amount_to_transfer);
        }

        if (remaining_unlocked_liquidity > 0) {
            emit LiquidityUnlocked(msg.sender, remaining_unlocked_liquidity);
        }
    }


    function _calculateNewPrincipal(Stake memory stake)
    internal view
    returns(uint256 principal)
    {
        principal = stake.amount;
        uint256 curr_block = block.number;

        if (stake.amount > 0)
        {
            // TODO(pb): There is more effective algorithm than this.
            uint256 start_block = stake.sinceBlock;
            for (uint64 i=stake.sinceInterestRateIndex; i < _interestRatesNextIdx; ++i) {
                InterestRatePerBlock storage interest = _interestRates[i];
                // TODO(pb): It is not strictly necessary to do this assert, and rather fully rely
                //           on correctness of `addInterestRate(...)` implementation.
                require(interest.sinceBlock <= start_block, "sinceBlock inconsistency");
                uint256 end_block = curr_block;

                uint64 j = i + 1;
                if (j < _interestRatesNextIdx) {
                    InterestRatePerBlock storage next_interest = _interestRates[j];
                    end_block = next_interest.sinceBlock;
                }

                principal = Finance.compoundInterest(principal, interest.rate, end_block - start_block);
                start_block = end_block;
            }
        }
    }


    function _collectLiquidity(Liquidity[] storage liquidities, uint256 at_block)
    internal
    returns(uint256 amount_unlocked)
    {
        for (uint256 i=0; i < liquidities.length; ) {
            Liquidity memory l = liquidities[i];

            if (l.liquidSinceBlock > at_block) {
                ++i;
                continue;
            }

            amount_unlocked += l.amount;
            // Copying last element of the array in to the current one,
            // so that the last one can be popped out of the array.
            uint256 last_idx = liquidities.length - 1;
            if (i != last_idx) {
                liquidities[i] = liquidities[last_idx];
            }
            // TODO: It will be cheaper (GAS consumption-wise) to simply leave
            // elements in array (do NOT delete them) and rather store "amortised"
            // size of the array in secondary separate store variable (= do NOT
            // use `array.length` as primary indication of array length).
            // Destruction of the array items is expensive. Excess of "allocated"
            // array storage can be left temporarily (or even permanently) unused.
            liquidities.pop();
        }
    }


    /**
     * @notice Updates Lock Period value
     * @param num_of_blocks  length of the lock period
     * @dev Delegate only
     *      SAFETY protection: max lock period value <= 584000 (= 1/4 of the Year = (365*24*60*60 / 13.5) / 4)
     */
    function updateLockPeriod(uint64 num_of_blocks)
    external
    onlyDelegate()
    {
        // NOTE
        require(num_of_blocks <= 584000, "Lock period must be max. 584000");
        _lockPeriodInBlocks = num_of_blocks;
        emit LockPeriod(num_of_blocks);
    }


    /**
     * @notice Pause the non-administrative interaction with the contract
     * @param block_number disallow non-admin. interactions with contract for a block.number >= block_number
     * @dev Delegate only
     */
    function pauseSince(uint256 block_number)
    external
    onlyDelegate()
    {
        _pausedSinceBlock = block_number < block.number ? block.number : block_number;
        emit Pause(_pausedSinceBlock);
    }


    /**
     * @notice Withdraw token balance
     * @param amount amount to withdraw
     * @param targetAddress address to send the tokens to
     * @dev to topup the contract simply send tokens to the contract address
     */
    function withDrawTokens(uint256 amount, address payable targetAddress)
    external
    onlyOwner()
    {
        require(_token.transfer(targetAddress, amount));
        emit TokenWithdrawal(targetAddress, amount);
    }


    /**
     * @notice Delete the contract, transfers the remaining token and ether balance to the specified
       payoutAddress
     * @param payoutAddress address to transfer the balances to. Ensure that this is able to handle ERC20 tokens
     * @dev owner only
     */
    function deleteContract(address payable payoutAddress)
    external
    onlyOwner()
    {
        uint256 contractBalance = _token.balanceOf(address(this));
        require(_token.transfer(payoutAddress, contractBalance));
        emit DeleteContract();
        selfdestruct(payoutAddress);
    }
}
