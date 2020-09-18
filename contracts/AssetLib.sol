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

import "../openzeppelin/contracts/math/SafeMath.sol";


library AssetLib {
    using SafeMath for uint256;


    struct Asset {
        uint256 principal;
        uint256 compoundInterest;
    }


    function composite(Asset storage asset)
        internal view returns(uint256)
    {
        return asset.principal.add(asset.compoundInterest);
    }


    function compositeM(Asset memory asset)
        internal pure returns(uint256)
    {
        return asset.principal.add(asset.compoundInterest);
    }


    function imAddS(Asset memory to, Asset storage amount)
        internal view
    {
        to.principal = to.principal.add(amount.principal);
        to.compoundInterest = to.compoundInterest.add(amount.compoundInterest);
    }


    function iAdd(Asset storage to, Asset memory amount)
        internal
    {
        to.principal = to.principal.add(amount.principal);
        to.compoundInterest = to.compoundInterest.add(amount.compoundInterest);
    }


    function imSubM(Asset memory from, Asset storage amount)
        internal view
    {
        from.principal = from.principal.sub(amount.principal);
        from.compoundInterest = from.compoundInterest.sub(amount.compoundInterest);
    }


    function iSub(Asset storage from, Asset memory amount)
        internal
    {
        from.principal = from.principal.sub(amount.principal);
        from.compoundInterest = from.compoundInterest.sub(amount.compoundInterest);
    }


    function iSubPrincipalFirst(Asset storage from, uint256 amount)
        internal returns(Asset memory _amount)
    {
        if (from.principal >= amount) {
            from.principal = from.principal.sub(amount);
            _amount.principal = amount;
        } else {
           _amount.compoundInterest = amount.sub(from.principal);
            // NOTE(pb): Fail as soon as possible (even though this ordering of lines makes code less readable):
            from.compoundInterest = from.compoundInterest.sub(_amount.compoundInterest);

            _amount.principal = from.principal;
            from.principal = 0;
        }
    }


    function iSubCompoundInterestFirst(Asset storage from, uint256 amount)
        internal returns(Asset memory _amount)
    {
        if (from.compoundInterest >= amount) {
            from.compoundInterest = from.compoundInterest.sub(amount);
            _amount.compoundInterest = amount;
        } else {
            _amount.principal = amount.sub(from.compoundInterest);
            // NOTE(pb): Fail as soon as possible (even though this ordering of lines makes code less readable):
            from.principal = from.principal.sub(_amount.principal);

            _amount.compoundInterest = from.compoundInterest;
            from.compoundInterest = 0;
        }
    }

    // NOTE(pb): This is a little bit more expensive version of the commented-out function bellow,
    //           but it avoids copying the code by reusing (calling existing functions), and so
    //           making code more reliable and readable.
    function iRelocatePrincipalFirst(Asset storage from, Asset storage to, uint256 amount)
        internal returns(Asset memory _amount)
    {
        _amount = iSubPrincipalFirst(from, amount);
        iAdd(to, _amount);
    }

    // NOTE(pb): This is a little bit more expensive version of the commented-out function bellow,
    //           but it avoids copying the code by reusing (calling existing functions), and so
    //           making code more reliable and readable.
    function iRelocateCompoundInterestFirst(Asset storage from, Asset storage to, uint256 amount)
        internal returns(Asset memory _amount)
    {
        _amount = iSubCompoundInterestFirst(from, amount);
        iAdd(to, _amount);
    }

    ////NOTE(pb): Whole Commented out code block bellow consumes less gas then variant above, however for the price
    ////          of copy code which can be rather called (see notes in the commented out code):
    //function iRelocatePrincipalFirst(Asset storage from, Asset storage to, uint256 amount)
    //    internal pure returns(Asset memory _amount)
    //{
    //    if (from.principal >= amount) {
    //        from.principal = from.principal.sub(amount);
    //        to.principal = to.principal.add(amount);
    //        // NOTE(pb): Line bellow is enough - no necessity to call subtract for compound as it is called in
    //        //           uncommented variant of this function above.
    //        _amount.principal = amount;
    //    } else {
    //        _amount.compoundInterest = amount.sub(from.principal);
    //        // NOTE(pb): Fail as soon as possible (even though this ordering of lines makes code less readable):
    //        from.compoundInterest = from.compoundInterest.sub(_amount.compoundInterest);
    //        to.compoundInterest = to.compoundInterest.add(_amount.compoundInterest);
    //        to.principal = to.principal.add(from.principal);

    //        _amount.principal = from.principal;
    //        // NOTE(pb): Line bellow is enough - no necessity to call subtract for principal as it is called in
    //        //           uncommented variant of this function above.
    //         from.principal = 0;
    //     }
    //}


    //function iRelocateCompoundInterestFirst(Asset storage from, Asset storage to, uint256 amount)
    //    internal pure returns(Asset memory _amount)
    //{
    //    if (from.compoundInterest >= amount) {
    //        from.compoundInterest = from.compoundInterest.sub(amount);
    //        to.compoundInterest = to.compoundInterest.add(amount);
    //        // NOTE(pb): Line bellow is enough - no necessity to call subtract for principal as it is called in
    //        //           uncommented variant of this function above.
    //        _amount.compoundInterest = amount;
    //    } else {
    //        _amount.principal = amount.sub(from.compoundInterest);
    //        // NOTE(pb): Fail as soon as possible (even though this ordering of lines makes code less readable):
    //        from.principal = from.principal.sub(_amount.principal);
    //        to.principal = to.principal.add(_amount.principal);
    //        to.compoundInterest = to.compoundInterest.add(from.compoundInterest);

    //        _amount.compoundInterest = from.compoundInterest;
    //        // NOTE(pb): Line bellow is enough - no necessity to call subtract for compound as it is called in
    //        //           uncommented variant of this function above.
    //         from.compoundInterest = 0;
    //    }
    //}
}
