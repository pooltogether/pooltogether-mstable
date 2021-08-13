// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.2;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IYieldSource } from "@pooltogether/yield-source-interface/contracts/IYieldSource.sol";
import { ISavingsContractV2 } from "@mstable/protocol/contracts/interfaces/ISavingsContract.sol";

contract MStableYieldSource is IYieldSource, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ISavingsContractV2 public immutable savings;
    IERC20 public immutable mAsset;

    /// @notice mapping of account addresses to interest-bearing mAsset balances. eg imUSD
    mapping(address => uint256) public imBalances;

    /// @notice Emitted on init
    /// @param savings The ISavingsContractV2 to bind to
    event Initialized(ISavingsContractV2 indexed savings);

    /// @notice Emitted when asset tokens are supplied to earn yield
    /// @param from The address who supplied the assets
    /// @param to The new owner of the assets
    /// @param amount The amount of assets supplied
    event Supplied(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when asset tokens are redeemed from the yield source
    /// @param from The address who is redeeming
    /// @param requestedAmount The amount that was requested to withdraw
    /// @param actualAmount The actual amount of assets transferred to the address
    event Redeemed(address indexed from, uint256 requestedAmount, uint256 actualAmount);

    constructor(ISavingsContractV2 _savings) ReentrancyGuard() {
        // As immutable storage variables can not be accessed in the constructor,
        // create in-memory variables that can be used instead.
        IERC20 mAssetMemory = IERC20(_savings.underlying());

        // infinite approve Savings Contract to transfer mAssets from this contract
        mAssetMemory.safeApprove(address(_savings), type(uint256).max);

        // save to immutable storage
        savings = _savings;
        mAsset = mAssetMemory;

        emit Initialized(_savings);
    }

    /// @notice Approve mStable savings contract to spend max uint256 amount of mAsset.
    /// @dev Emergency function to re-approve max amount if approval amount dropped too low.
    /// @return true if operation is successful.
    function approveMaxAmount() external returns (bool) {
        IERC20 _mAsset = mAsset;
        address _savings = address(savings);

        uint256 _allowance = _mAsset.allowance(address(this), _savings);
        _mAsset.safeIncreaseAllowance(_savings, type(uint256).max - _allowance);

        return true;
    }

    /// @notice Returns the ERC20 mAsset token used for deposits.
    /// @return mAsset token address. eg mUSD
    function depositToken() external view override returns (address) {
        return address(mAsset);
    }

    /// @notice Returns the total balance (in asset tokens).  This includes the deposits and interest.
    /// @return mAssets The underlying balance of mAsset tokens. eg mUSD
    function balanceOfToken(address addr) external view override returns (uint256 mAssets) {
        uint256 exchangeRate = savings.exchangeRate();
        mAssets = (imBalances[addr] * exchangeRate) / 1e18;
    }

    /// @notice Deposits mAsset tokens to the savings contract.
    /// @param _mAssetAmount The amount of mAsset tokens to be deposited. eg mUSD
    function supplyTokenTo(uint256 _mAssetAmount, address _to) external override nonReentrant {
        mAsset.safeTransferFrom(msg.sender, address(this), _mAssetAmount);
        imBalances[_to] += savings.depositSavings(_mAssetAmount);

        emit Supplied(msg.sender, _to, _mAssetAmount);
    }

    /// @notice Redeems mAsset tokens from the interest-beaing mAsset.
    ///         eg. redeems mUSD from imUSD.
    /// @param mAssetAmount The amount of mAsset tokens requested to be redeemed. eg mUSD
    /// @return mAssetsActual The actual amount of mAsset tokens that were received from the redeem. eg mUSD
    function redeemToken(uint256 mAssetAmount)
        external
        override
        nonReentrant
        returns (uint256 mAssetsActual)
    {
        uint256 mAssetBalanceBefore = mAsset.balanceOf(address(this));

        uint256 creditsBurned = savings.redeemUnderlying(mAssetAmount);

        imBalances[msg.sender] -= creditsBurned;
        uint256 mAssetBalanceAfter = mAsset.balanceOf(address(this));
        mAssetsActual = mAssetBalanceAfter - mAssetBalanceBefore;

        mAsset.safeTransfer(msg.sender, mAssetsActual);

        emit Redeemed(msg.sender, mAssetAmount, mAssetsActual);
    }
}
