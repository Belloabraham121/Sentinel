// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ICompoundV3Comet
 * @notice Interface for Compound V3 Comet contract
 * @dev This interface contains the core functions needed for liquidations and account management
 */
interface ICompoundV3Comet {
    /**
     * @notice Configuration for an asset
     */
    struct AssetInfo {
        uint8 offset;
        address asset;
        address priceFeed;
        uint64 scale;
        uint64 borrowCollateralFactor;
        uint64 liquidateCollateralFactor;
        uint64 liquidationFactor;
        uint128 supplyCap;
    }

    /**
     * @notice User's basic account information
     */
    struct UserBasic {
        int104 principal;
        uint64 baseTrackingIndex;
        uint64 baseTrackingAccrued;
        uint16 assetsIn;
        uint8 _reserved;
    }

    /**
     * @notice User's collateral balance for a specific asset
     */
    struct UserCollateral {
        uint128 balance;
        uint128 _reserved;
    }

    /**
     * @notice Absorb a list of underwater accounts onto the protocol balance sheet
     * @param absorber The account performing the absorption
     * @param accounts The list of underwater accounts to absorb
     */
    function absorb(address absorber, address[] calldata accounts) external;

    /**
     * @notice Buy collateral from the protocol using base tokens, increasing protocol reserves
     * @param asset The asset to buy
     * @param minAmount The minimum amount of collateral tokens to receive
     * @param baseAmount The amount of base tokens to pay
     * @param recipient The recipient address
     */
    function buyCollateral(
        address asset,
        uint256 minAmount,
        uint256 baseAmount,
        address recipient
    )
        external;

    /**
     * @notice Supply an amount of asset to the protocol
     * @param asset The asset to supply
     * @param amount The quantity to supply
     */
    function supply(address asset, uint256 amount) external;

    /**
     * @notice Supply an amount of asset to dst
     * @param dst The address which will hold the balance
     * @param asset The asset to supply
     * @param amount The quantity to supply
     */
    function supplyTo(address dst, address asset, uint256 amount) external;

    /**
     * @notice Supply an amount of asset from `from` to dst, if allowed
     * @param from The supplier address
     * @param dst The address which will hold the balance
     * @param asset The asset to supply
     * @param amount The quantity to supply
     */
    function supplyFrom(address from, address dst, address asset, uint256 amount) external;

    /**
     * @notice Transfer an amount of asset from src to dst, if allowed
     * @param src The sender address
     * @param dst The recipient address
     * @param asset The asset to transfer
     * @param amount The quantity to transfer
     */
    function transferAsset(address src, address dst, address asset, uint256 amount) external;

    /**
     * @notice Transfer an amount of asset from src to dst, if allowed
     * @param src The sender address
     * @param dst The recipient address
     * @param asset The asset to transfer
     * @param amount The quantity to transfer
     */
    function transferAssetFrom(address src, address dst, address asset, uint256 amount) external;

    /**
     * @notice Withdraw an amount of asset from the protocol
     * @param asset The asset to withdraw
     * @param amount The quantity to withdraw
     */
    function withdraw(address asset, uint256 amount) external;

    /**
     * @notice Withdraw an amount of asset to dst
     * @param dst The address which will receive the withdrawal
     * @param asset The asset to withdraw
     * @param amount The quantity to withdraw
     */
    function withdrawTo(address dst, address asset, uint256 amount) external;

    /**
     * @notice Withdraw an amount of asset from src to dst, if allowed
     * @param src The supplier address
     * @param dst The address which will receive the withdrawal
     * @param asset The asset to withdraw
     * @param amount The quantity to withdraw
     */
    function withdrawFrom(address src, address dst, address asset, uint256 amount) external;

    /**
     * @notice Approve `manager` to act on behalf of the sender
     * @param manager The account which will be approved
     * @param isAllowed_ Whether or not to approve the manager
     */
    function allow(address manager, bool isAllowed_) external;

    /**
     * @notice Approve `manager` to act on behalf of the sender, with a valid signature
     * @param owner The owner address
     * @param manager The manager address
     * @param isAllowed_ Whether or not to approve the manager
     * @param nonce The signing nonce
     * @param expiry The signature expiry
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function allowBySig(
        address owner,
        address manager,
        bool isAllowed_,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external;

    /**
     * @notice Get the current collateral balance of an account for an asset
     * @param account The account to check
     * @param asset The asset to check
     * @return The collateral balance
     */
    function collateralBalanceOf(address account, address asset) external view returns (uint128);

    /**
     * @notice Get the current base balance of an account
     * @param account The account to check
     * @return The base balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get the current borrowed balance of an account
     * @param account The account to check
     * @return The borrowed balance
     */
    function borrowBalanceOf(address account) external view returns (uint256);

    /**
     * @notice Check if an account is liquidatable
     * @param account The account to check
     * @return Whether the account is liquidatable
     */
    function isLiquidatable(address account) external view returns (bool);

    /**
     * @notice Check if an account is underwater (borrowing more than collateral allows)
     * @param account The account to check
     * @return Whether the account is underwater
     */
    function isBorrowCollateralized(address account) external view returns (bool);

    /**
     * @notice Check if an account has enough collateral to withdraw an amount
     * @param account The account to check
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw
     * @return Whether the withdrawal is allowed
     */
    function isWithdrawAllowed(
        address account,
        address asset,
        uint256 amount
    )
        external
        view
        returns (bool);

    /**
     * @notice Get account's basic information
     * @param account The account to check
     * @return The account's basic information
     */
    function userBasic(address account) external view returns (UserBasic memory);

    /**
     * @notice Get account's collateral information for a specific asset
     * @param account The account to check
     * @param asset The asset to check
     * @return The account's collateral information
     */
    function userCollateral(
        address account,
        address asset
    )
        external
        view
        returns (UserCollateral memory);

    /**
     * @notice Get the current utilization rate
     * @return The utilization rate
     */
    function getUtilization() external view returns (uint256);

    /**
     * @notice Get the current supply rate
     * @param utilization The utilization rate
     * @return The supply rate
     */
    function getSupplyRate(uint256 utilization) external view returns (uint256);

    /**
     * @notice Get the current borrow rate
     * @param utilization The utilization rate
     * @return The borrow rate
     */
    function getBorrowRate(uint256 utilization) external view returns (uint256);

    /**
     * @notice Get asset information by index
     * @param i The asset index
     * @return The asset information
     */
    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);

    /**
     * @notice Get asset information by asset address
     * @param asset The asset address
     * @return The asset information
     */
    function getAssetInfoByAddress(address asset) external view returns (AssetInfo memory);

    /**
     * @notice Get the price from the protocol's price feed
     * @param priceFeed The price feed address
     * @return The price
     */
    function getPrice(address priceFeed) external view returns (uint256);

    /**
     * @notice Quote collateral amount for base amount
     * @param asset The collateral asset
     * @param baseAmount The base amount
     * @return The collateral amount
     */
    function quoteCollateral(address asset, uint256 baseAmount) external view returns (uint256);

    /**
     * @notice Get the total number of assets
     * @return The total number of assets
     */
    function numAssets() external view returns (uint8);

    /**
     * @notice Get the decimals of the base token
     * @return The decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get the base token address
     * @return The base token address
     */
    function baseToken() external view returns (address);

    /**
     * @notice Get the base token price feed address
     * @return The base token price feed address
     */
    function baseTokenPriceFeed() external view returns (address);

    /**
     * @notice Get the extension delegate address
     * @return The extension delegate address
     */
    function extensionDelegate() external view returns (address);

    /**
     * @notice Get the supply kink utilization rate
     * @return The supply kink
     */
    function supplyKink() external view returns (uint256);

    /**
     * @notice Get the supply rate at kink utilization
     * @return The supply rate at kink
     */
    function supplyPerYearInterestRateBase() external view returns (uint256);

    /**
     * @notice Get the supply rate slope below kink
     * @return The supply rate slope below kink
     */
    function supplyPerYearInterestRateSlopeLow() external view returns (uint256);

    /**
     * @notice Get the supply rate slope above kink
     * @return The supply rate slope above kink
     */
    function supplyPerYearInterestRateSlopeHigh() external view returns (uint256);

    /**
     * @notice Get the borrow kink utilization rate
     * @return The borrow kink
     */
    function borrowKink() external view returns (uint256);

    /**
     * @notice Get the borrow rate at zero utilization
     * @return The borrow rate at zero utilization
     */
    function borrowPerYearInterestRateBase() external view returns (uint256);

    /**
     * @notice Get the borrow rate slope below kink
     * @return The borrow rate slope below kink
     */
    function borrowPerYearInterestRateSlopeLow() external view returns (uint256);

    /**
     * @notice Get the borrow rate slope above kink
     * @return The borrow rate slope above kink
     */
    function borrowPerYearInterestRateSlopeHigh() external view returns (uint256);

    /**
     * @notice Get the factor for reserve purchases of collateral
     * @return The store front price factor
     */
    function storeFrontPriceFactor() external view returns (uint256);

    /**
     * @notice Get the scale factor for base tracking
     * @return The base tracking supply speed
     */
    function baseTrackingSupplySpeed() external view returns (uint256);

    /**
     * @notice Get the scale factor for base tracking borrows
     * @return The base tracking borrow speed
     */
    function baseTrackingBorrowSpeed() external view returns (uint256);

    /**
     * @notice Get the minimum base amount for rewards accrual
     * @return The base minimum for rewards
     */
    function baseMinForRewards() external view returns (uint256);

    /**
     * @notice Get the minimum base amount for borrow
     * @return The base borrow minimum
     */
    function baseBorrowMin() external view returns (uint256);

    /**
     * @notice Get the protocol's target reserves
     * @return The target reserves
     */
    function targetReserves() external view returns (uint256);

    /**
     * @notice Get the total supply of base tokens
     * @return The total supply
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Get the total borrow of base tokens
     * @return The total borrow
     */
    function totalBorrow() external view returns (uint256);

    /**
     * @notice Get the protocol reserves
     * @return The reserves
     */
    function getReserves() external view returns (int256);

    /**
     * @notice Check if manager is allowed for owner
     * @param owner The owner address
     * @param manager The manager address
     * @return Whether manager is allowed
     */
    function isAllowed(address owner, address manager) external view returns (bool);

    /**
     * @notice Get the nonce for permit
     * @param owner The owner address
     * @return The nonce
     */
    function userNonce(address owner) external view returns (uint256);
}
