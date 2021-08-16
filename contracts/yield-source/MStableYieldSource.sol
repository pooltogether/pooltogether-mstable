// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IYieldSource } from "@pooltogether/yield-source-interface/contracts/IYieldSource.sol";
import { ISavingsContractV2 } from "@mstable/protocol/contracts/interfaces/ISavingsContract.sol";

contract MStableYieldSource is IYieldSource, Ownable, ReentrancyGuard {
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

    /// @notice Emitted when asset tokens are redeemed from the yield source.
    /// @param from Address who is redeeming.
    /// @param requestedAmount Amount that was requested to withdraw.
    /// @param actualAmount Actual amount of assets transferred to the address.
    event Redeemed(address indexed from, uint256 requestedAmount, uint256 actualAmount);

    constructor(ISavingsContractV2 _savings) ReentrancyGuard() {
        require(address(_savings) != address(0), "MStableYieldSource/savings-not-zero-address");

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
    function approveMaxAmount() external onlyOwner returns (bool) {
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
    /// @return Underlying balance of mAsset tokens. eg mUSD
    function balanceOfToken(address addr) external view override returns (uint256) {
        uint256 exchangeRate = savings.exchangeRate();

        // userSavings = userCredits * exchangeRate
        return (imBalances[addr] * exchangeRate) / 1e18;
    }

    /// @notice Deposits mAsset tokens to the savings contract.
    /// @param _mAssetAmount The amount of mAsset tokens to be deposited. eg mUSD
    function supplyTokenTo(uint256 _mAssetAmount, address _to) external override nonReentrant {
        mAsset.safeTransferFrom(msg.sender, address(this), _mAssetAmount);

        // Add units of credits (imUSD) issued to sender balance
        imBalances[_to] += savings.depositSavings(_mAssetAmount);

        emit Supplied(msg.sender, _to, _mAssetAmount);
    }

    /// @notice Redeems mAsset tokens from the interest-bearing mAsset. eg. redeems mUSD from imUSD.
    /// @dev We perform an unchecked substraction of mAsset tokens
    /// @dev cause `mAssetBalanceAfter` will always be superior or at least equal to `mAssetBalanceBefore`
    /// @dev so no need to check for underflow or overflow.
    /// @param _amount Amount of mAsset tokens to redeem. eg mUSD.
    /// @return _mAssetRedeemed Actual amount of mAsset tokens that were redeemed. eg mUSD.
    function redeemToken(uint256 _amount)
        external
        override
        nonReentrant
        returns (uint256 _mAssetRedeemed)
    {
        uint256 _mAssetBalanceBefore = mAsset.balanceOf(address(this));

        // Substracts units of credits (imUSD) burned from sender balance
        imBalances[msg.sender] -= savings.redeemUnderlying(_amount);

        uint256 _mAssetBalanceAfter = mAsset.balanceOf(address(this));

        unchecked { _mAssetRedeemed = _mAssetBalanceAfter - _mAssetBalanceBefore; }

        mAsset.safeTransfer(msg.sender, _mAssetRedeemed);

        emit Redeemed(msg.sender, _amount, _mAssetRedeemed);
    }
}
