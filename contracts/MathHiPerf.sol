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

library MathHiPerf {
    function chineseReminder(uint256 x0, uint256 x1)
        internal pure
        returns(uint256 r0, uint256 r1)
    {
        //r0 = x0;
        //r1 = x1 - x0 - (x1 < x0 ? 1 : 0);

        // Optimised version of the above code (it might no longer be necessary
        // for solidity compiler ver >= 0.6.0:
        assembly {
            r0 := x0
            r1 := sub(sub(x1, x0), lt(x1, x0))
        }
    }

    function div256by(uint256 a)
        internal pure
        returns(uint256 r)
    {
        require(a > 1);
        assembly {
            r := add(div(sub(0, a), a), 1)
        }
    }

    function mod256by(uint256 a)
        internal pure
        returns(uint256 r)
    {
        require(a != 0);
        assembly {
            r := mod(sub(0, a), a)
        }
    }

    //[1, 11, 13, 7, 9, 3, 5, 15]
    // 4 bit lookup table
    //bytes16 constant modularMultiplicativeInv256LookupTable = 0x0001000b000d0007000900030005000f;

    // a.r equiv 1 (mod m) => r equiv a**(-1) (mod m) =>
    function modularMultiplicativeInv256(uint256 a)
        internal pure
        returns(uint256 r)
    {
        //[1, 11, 13, 7, 9, 3, 5, 15]
        // 4 bit lookup table
        bytes16 table = 0x0001000b000d0007000900030005000f;
        assembly {
            r := byte(and(15, a), table)
        }

        // 6 iterations of Newton-Raphson for 4 x (1<<6) = 256 bit
        r *= 2 - a * r;
        r *= 2 - a * r;
        r *= 2 - a * r;
        r *= 2 - a * r;
        r *= 2 - a * r;
        r *= 2 - a * r;
        return r;
    }

    function add512(uint256 a0, uint256 a1, uint256 b0, uint256 b1)
        internal pure
        returns(uint256 r0, uint256 r1)
    {
        assembly {
            r0 := add(a0, b0)
            r1 := add(add(a1, b1), lt(r0, a0))
        }
    }

    function sub512(uint256 a0, uint256 a1, uint256 b0, uint256 b1)
        internal pure
        returns(uint256 r0, uint256 r1)
    {
        assembly {
            r0 := sub(a0, b0)
            r1 := sub(sub(a1, b1), lt(a0, b0))
        }
    }

    uint256 constant M1 = ~uint256(0); //2**256 - 1;

    function mul512(uint256 a, uint256 b)
        internal pure
        returns(uint256 r0, uint256 r1)
    {
        //uint256 x0 = a * b;
        //uint256 x1 = mulmod(a, b, M1);
        //(r0, r1) = chineseReminder(x0, x1);
        //return (r0, r1);

        // Optimised version of the above code (it might no longer be necessary
        // for solidity compiler ver >= 0.6.0:
        assembly {
            let mm := mulmod(a, b, not(0))
            r0 := mul(a, b)
            r1 := sub(sub(mm, r0), lt(mm, r0))
        }
    }

    // This division is NOT fully optimised. In order to cut the performance
    // close to the possible maximum, we need to utilise here the
    // `modularMultiplicativeInv256(...)` function.
    function div512(uint256 a0, uint256 a1, uint256 b)
        internal pure
        returns(uint256 x0, uint256 x1)
    {
        if (b == 1) {
            return (a0, a1);
        }

        uint256 q = div256by(b);
        uint256 r = mod256by(b);
        uint256 t0 = 0;
        uint256 t1 = 0;

        while (a1 != 0) {
            (t0, t1) = mul512(a1, q);
            (x0, x1) = add512(x0, x1, t0, t1);
            (t0, t1) = mul512(a1, r);
            (a0, a1) = add512(t0, t1, a0, 0);
        }
        (x0, x1) = add512(x0, x1, a0/b, 0);
        return (x0, x1);
    }
}
