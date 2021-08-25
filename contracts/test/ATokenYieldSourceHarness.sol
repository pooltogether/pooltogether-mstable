// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISavingsContractV2 } from "@mstable/protocol/contracts/interfaces/ISavingsContract.sol";

import "../yield-source/MStableYieldSource.sol";

/* solium-disable security/no-block-members */
contract MStableYieldSourceHarness is MStableYieldSource {
    using SafeERC20 for IERC20;

    constructor(ISavingsContractV2 _savings) MStableYieldSource(_savings) {}

    function decreaseAllowance(IERC20 token, address spender, uint256 value) external returns (bool) {
        token.safeDecreaseAllowance(spender, value);
        return true;
    }
}
