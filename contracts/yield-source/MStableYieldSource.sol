// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.6;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IYieldSource } from "@pooltogether/yield-source-interface/contracts/IYieldSource.sol";
import { ISavingsContractV2 } from "@mstable/protocol/contracts/interfaces/ISavingsContract.sol";

import "../access/AssetManager.sol";

/// @title mStable yield source integration contract, implementing PoolTogether's generic yield source interface.
/// @dev This contract adheres to the PoolTogether yield source interface.
/// @dev This contract inherits AssetManager which extends Ownable.
/// @notice Yield source for a PoolTogether prize pool that generates yield by depositing into mStable savings contract.
contract MStableYieldSource is IYieldSource, AssetManager, ReentrancyGuard {
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

    /// @notice Emitted when ERC20 tokens other than yield source's tokens are withdrawn from the mStable yield source.
    /// @param from Address that transferred funds.
    /// @param to Address that received funds.
    /// @param amount Amount of tokens transferred.
    /// @param token ERC20 token transferred.
    event TransferredERC20(
        address indexed from,
        address indexed to,
        uint256 amount,
        IERC20 indexed token
    );

    constructor(ISavingsContractV2 _savings) Ownable() ReentrancyGuard() {
        require(address(_savings) != address(0), "MStableYieldSource/savings-not-zero-address");

        // As immutable storage variables can not be accessed in the constructor,
        // create in-stack variable that can be used instead.
        IERC20 _mAsset = IERC20(_savings.underlying());

        // Infinite approve Savings Contract to transfer mAssets from this contract
        _mAsset.safeApprove(address(_savings), type(uint256).max);

        // Save to immutable storage
        savings = _savings;
        mAsset = _mAsset;

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
    /// @param _addr User address.
    /// @return Underlying balance of mAsset tokens. eg mUSD.
    function balanceOfToken(address _addr) external view override returns (uint256) {
        // userSavings = userCredits * exchangeRate
        return (imBalances[_addr] * savings.exchangeRate()) / 1e18;
    }

    /// @notice Deposits mAsset tokens to the savings contract.
    /// @param _amount The amount of mAsset tokens to be deposited. eg mUSD.
    /// @param _to User address whose balance will receive the tokens.
    function supplyTokenTo(uint256 _amount, address _to) external override nonReentrant {
        mAsset.safeTransferFrom(msg.sender, address(this), _amount);

        // Add units of credits (imUSD) issued to sender balance
        imBalances[_to] += savings.depositSavings(_amount);

        emit Supplied(msg.sender, _to, _amount);
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

        unchecked {
            _mAssetRedeemed = _mAssetBalanceAfter - _mAssetBalanceBefore;
        }

        mAsset.safeTransfer(msg.sender, _mAssetRedeemed);

        emit Redeemed(msg.sender, _amount, _mAssetRedeemed);
    }

    /// @notice Transfer ERC20 tokens other than the imAsset tokens held by this contract to the recipient address.
    /// @dev This function is only callable by the owner or asset manager.
    /// @param _erc20Token ERC20 token to transfer.
    /// @param _to Recipient of the tokens.
    /// @param _amount Amount of tokens to transfer.
    function transferERC20(
        IERC20 _erc20Token,
        address _to,
        uint256 _amount
    ) external onlyOwnerOrAssetManager {
        require(
            address(_erc20Token) != address(savings),
            "MStableYieldSource/imAsset-transfer-not-allowed"
        );

        _erc20Token.safeTransfer(_to, _amount);
        emit TransferredERC20(msg.sender, _to, _amount, _erc20Token);
    }
}
