pragma solidity ^0.6.0;

import "./abdk-libraries/ABDKMath64x64.sol";


library Finance {

    function pow (int128 x, uint256 n)
        internal pure returns (int128 r)
    {
        r = ABDKMath64x64.fromUInt (1);

        while (n > 0) {
            if (n & 1 > 0) {
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

    function compoundInterest (uint256 principal, int128 ratio_64_64, uint256 n)
        internal pure returns (uint256)
    {
        return ABDKMath64x64.mulu (
            pow (
                ABDKMath64x64.add (
                    ABDKMath64x64.fromUInt (1),
                    ratio_64_64
                    ),
                    n
                ),
            principal);
    }
}
