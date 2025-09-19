// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAaveV3Oracle
 * @notice Interface for Aave V3 Oracle contract
 * @dev This interface provides price feed functionality for Aave V3 protocol
 */
interface IAaveV3Oracle {
    /**
     * @notice Returns the asset price in the base currency
     * @param asset The address of the asset
     * @return The price of the asset
     */
    function getAssetPrice(address asset) external view returns (uint256);

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param assets The list of assets addresses
     * @return The prices of the given assets
     */
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    /**
     * @notice Returns the address of the source of an asset
     * @param asset The address of the asset
     * @return The address of the source of the asset
     */
    function getSourceOfAsset(address asset) external view returns (address);

    /**
     * @notice Returns the address of the fallback oracle
     * @return The address of the fallback oracle
     */
    function getFallbackOracle() external view returns (address);

    /**
     * @notice Returns the base currency address
     * @dev Address 0x0 is used for USD as base currency.
     * @return The base currency address.
     */
    function BASE_CURRENCY() external view returns (address);

    /**
     * @notice Returns the base currency unit
     * @return The base currency unit
     */
    function BASE_CURRENCY_UNIT() external view returns (uint256);

    /**
     * @notice Sets or replaces price sources of assets
     * @param assets The addresses of the assets
     * @param sources The addresses of the price sources
     */
    function setAssetSources(address[] calldata assets, address[] calldata sources) external;

    /**
     * @notice Sets the fallback oracle
     * @param fallbackOracle The address of the fallback oracle
     */
    function setFallbackOracle(address fallbackOracle) external;
}
