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

import "../abdk-libraries/ABDKMath64x64.sol";
import "./AssetLib.sol";


library Finance {
    using SafeMath for uint256;
    using AssetLib for AssetLib.Asset;


    function pow (int128 x, uint256 n)
        internal pure returns (int128 r)
    {
        r = ABDKMath64x64.fromUInt (1);

        while (n != 0) {
            if ((n & 1) != 0) {
                r = ABDKMath64x64.mul (r, x);
                n -= 1;
            } else {
                x = ABDKMath64x64.mul (x, x);
                n >>= 1;
            }
        }
    }


    function compoundInterest (uint256 principal, uint256 ratio, uint256 n)
        internal pure returns (uint256)
    {
        return ABDKMath64x64.mulu (
            pow (
                ABDKMath64x64.add (
                    ABDKMath64x64.fromUInt (1),
                    ABDKMath64x64.divu (
                          ratio,
                          10**18)
                    ),
                    n
                ),
            principal);
    }


    function compoundInterest (uint256 principal, int256 ratio, uint256 n)
        internal pure returns (uint256)
    {
        return ABDKMath64x64.mulu (
            pow (
                ABDKMath64x64.add (
                    ABDKMath64x64.fromUInt (1),
                    ABDKMath64x64.divi (
                          ratio,
                          10**18)
                    ),
                    n
                ),
            principal);
    }


    function compoundInterest (AssetLib.Asset storage asset, uint256 interest, uint256 n)
        internal
    {
        uint256 composite = asset.composite();
        composite = compoundInterest(composite, interest, n);

        asset.compoundInterest = composite.sub(asset.principal);
    }
}
