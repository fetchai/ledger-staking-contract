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

import "./Staking.sol";


contract StakingMock is Staking {
    uint256 public _blockNumber;

    constructor(
          address ERC20Address
        , uint256 interestRatePerBlock
        , uint256 pausedSinceBlock
        , uint64  lockPeriodInBlocks) 
    public Staking(
        ERC20Address, interestRatePerBlock, pausedSinceBlock, lockPeriodInBlocks)
    {
        // NOTE(pb): Unnecessary, only wastes gas. The data mamber is implicitly initialised to default value( zero in the case of integral types). 
        //_blockNumber = 0;
    }


    function _getBlockNumber() internal view override returns(uint256) {
        return _blockNumber;
    }


    function setBlockNumber(uint256 blockNumber) public {
        _blockNumber = blockNumber;
    }
}
