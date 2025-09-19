// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Uniswap V4 imports
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { BaseTestHooks } from "v4-core/src/test/BaseTestHooks.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { BalanceDelta } from "v4-core/src/types/BalanceDelta.sol";
import { BeforeSwapDelta, BeforeSwapDeltaLibrary } from "v4-core/src/types/BeforeSwapDelta.sol";
import { StateLibrary } from "v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "v4-core/test/utils/LiquidityAmounts.sol";
import { Position } from "v4-core/src/libraries/Position.sol";

// Security imports
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

// Protocol interfaces
import { IAaveV3Pool } from "./interfaces/IAaveV3Pool.sol";
import { IAaveV3Oracle } from "./interfaces/IAaveV3Oracle.sol";
import { ICompoundV3Comet } from "./interfaces/ICompoundV3Comet.sol";
import { IChainlinkAggregator } from "./interfaces/IChainlinkAggregator.sol";

/**
 * @title Lending Liquidity Guardian Hook
 * @notice A Uniswap V4 hook that combines automated liquidations for lending protocols
 *         with intelligent liquidity position optimization
 * @dev Implements beforeSwap and afterSwap hooks to automate loan liquidations and optimize LP positions
 */
contract LendingLiquidityGuardianHook is BaseTestHooks, Ownable, ReentrancyGuard, Pausable {
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using PoolIdLibrary for PoolKey;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event LiquidationExecuted(
        address indexed liquidator,
        address indexed borrower,
        address indexed collateralAsset,
        address debtAsset,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 liquidationBonus
    );

    event PositionRebalanced(
        PoolKey indexed poolKey,
        address indexed positionOwner,
        int24 oldTickLower,
        int24 oldTickUpper,
        int24 newTickLower,
        int24 newTickUpper
    );

    event TickRangeUpdated(
        bytes32 indexed poolId,
        bytes32 indexed protocolAdapter,
        int24 currentTick,
        uint256 volatilityScore
    );

    event ProtocolAdapterUpdated(address indexed protocol, address indexed adapter, bool enabled);

    // =============================================================================
    // ERRORS
    // =============================================================================

    error InvalidHealthFactor();
    error LiquidationFailed();
    error UnauthorizedLiquidator();
    error InvalidProtocolAdapter();
    error PositionNotOutOfRange();
    error RebalancingFailed();
    error InvalidTickRange();
    error InsufficientLiquidationBonus();

    // =============================================================================
    // STRUCTS
    // =============================================================================

    struct LiquidationData {
        address borrower;
        address collateralAsset;
        address debtAsset;
        uint256 debtToCover;
        bool receiveAToken;
        address protocolAdapter;
    }

    struct RebalanceData {
        address positionOwner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        bool autoRebalanceEnabled;
    }

    struct ProtocolAdapter {
        address adapterAddress;
        bool enabled;
        uint256 liquidationThreshold; // Health factor threshold (scaled by 1e18)
    }

    // Additional data structures for LP position management
    struct LPPositionInfo {
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
        uint256 lastUpdateTimestamp;
        uint256 feesEarned0;
        uint256 feesEarned1;
    }

    struct TickMonitoringData {
        int24[] tickHistory;
        uint256 lastUpdateTimestamp;
        uint256 volatilityScore;
        uint256 averageTickMovement;
    }

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    /// @notice The pool manager instance
    IPoolManager public immutable poolManager;

    /// @notice Mapping of protocol adapters (Aave, Compound, etc.)
    mapping(address => ProtocolAdapter) public protocolAdapters;

    /// @notice Mapping of position data for rebalancing
    mapping(bytes32 => RebalanceData) public positionData;

    /// @notice Mapping of authorized liquidators
    mapping(address => bool) public authorizedLiquidators;

    // Mappings for LP position tracking
    mapping(bytes32 => mapping(bytes32 => LPPositionInfo)) public lpPositions; // poolId => protocolAdapter => position
    mapping(bytes32 => mapping(bytes32 => TickMonitoringData)) public tickMonitoring; // poolId => protocolAdapter => monitoring

    /// @notice Default liquidation threshold (1.05 = 105% health factor)
    uint256 public constant DEFAULT_LIQUIDATION_THRESHOLD = 1.05e18;

    /// @notice Minimum liquidation bonus (5%)
    uint256 public constant MIN_LIQUIDATION_BONUS = 0.05e18;

    /// @notice Maximum tick deviation for rebalancing (500 ticks)
    int24 public constant MAX_TICK_DEVIATION = 500;

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    constructor(IPoolManager _poolManager) BaseTestHooks() Ownable(msg.sender) {
        poolManager = _poolManager;
    }

    // =============================================================================
    // HOOK IMPLEMENTATIONS
    // =============================================================================

    /**
     * @notice Hook called before a swap to check for liquidation opportunities
     * @param sender The address initiating the swap
     * @param key The pool key
     * @param params The swap parameters
     * @param hookData Encoded liquidation data
     * @return selector The function selector
     * @return beforeSwapDelta The delta for the hook
     * @return lpFeeOverride Optional LP fee override
     */
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    )
        external
        override
        nonReentrant
        whenNotPaused
        returns (bytes4 selector, BeforeSwapDelta beforeSwapDelta, uint24 lpFeeOverride)
    {
        // Decode liquidation data if provided
        if (hookData.length > 0) {
            LiquidationData memory liquidationData = abi.decode(hookData, (LiquidationData));

            // Verify liquidation conditions
            if (_shouldExecuteLiquidation(liquidationData)) {
                _executeLiquidation(sender, key, params, liquidationData);
            }
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @notice Hook called after a swap to check for rebalancing opportunities
     * @param sender The address that initiated the swap
     * @param key The pool key
     * @param params The swap parameters
     * @param delta The balance delta from the swap
     * @param hookData Encoded rebalance data
     * @return selector The function selector
     * @return hookDelta The hook's delta
     */
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    )
        external
        override
        nonReentrant
        whenNotPaused
        returns (bytes4 selector, int128 hookDelta)
    {
        // Only process if this is a liquidation-related swap
        if (hookData.length > 0) {
            LiquidationData memory liquidationData = abi.decode(hookData, (LiquidationData));

            // Check if LP position rebalancing is needed
            _checkAndRebalanceLPPosition(key, liquidationData, delta);

            // Monitor tick ranges for optimal positioning
            _monitorTickRanges(key, liquidationData);
        }

        // Check for rebalancing opportunities
        bytes32 positionId = _getPositionId(key, sender);
        RebalanceData storage position = positionData[positionId];

        if (position.autoRebalanceEnabled && _shouldRebalancePosition(key, position)) {
            _rebalancePosition(key, position);
        }

        return (IHooks.afterSwap.selector, 0);
    }

    /**
     * @notice Check and rebalance LP position after liquidation
     * @param key The pool key
     * @param liquidationData The liquidation data
     * @param delta The balance delta from the swap
     */
    function _checkAndRebalanceLPPosition(
        PoolKey calldata key,
        LiquidationData memory liquidationData,
        BalanceDelta delta
    )
        internal
    {
        // Get current pool state
        (uint160 sqrtPriceX96, int24 tick,,) = StateLibrary.getSlot0(poolManager, key.toId());

        // Check if current tick is outside optimal range
        int24 optimalLowerTick = _calculateOptimalLowerTick(
            tick, bytes32(uint256(uint160(liquidationData.protocolAdapter)))
        );
        int24 optimalUpperTick = _calculateOptimalUpperTick(
            tick, bytes32(uint256(uint160(liquidationData.protocolAdapter)))
        );

        // Get current LP position info
        LPPositionInfo memory currentPosition = lpPositions[PoolId.unwrap(key.toId())][bytes32(
            uint256(uint160(liquidationData.protocolAdapter))
        )];

        // Check if rebalancing is needed
        if (_shouldRebalancePosition(currentPosition, optimalLowerTick, optimalUpperTick, tick)) {
            _executePositionRebalancing(
                key,
                bytes32(uint256(uint160(liquidationData.protocolAdapter))),
                currentPosition,
                optimalLowerTick,
                optimalUpperTick,
                delta
            );
        }
    }

    /**
     * @notice Monitor tick ranges for position optimization
     * @param key The pool key
     * @param liquidationData The liquidation data
     */
    function _monitorTickRanges(
        PoolKey calldata key,
        LiquidationData memory liquidationData
    )
        internal
    {
        (, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, key.toId());

        // Update tick monitoring data
        TickMonitoringData storage monitoringData = tickMonitoring[PoolId.unwrap(key.toId())][bytes32(
            uint256(uint160(liquidationData.protocolAdapter))
        )];

        // Update price movement tracking
        monitoringData.lastUpdateTimestamp = block.timestamp;
        monitoringData.tickHistory.push(currentTick);

        // Keep only recent tick history (last 100 entries)
        if (monitoringData.tickHistory.length > 100) {
            // Remove oldest entry
            for (uint256 i = 0; i < monitoringData.tickHistory.length - 1; i++) {
                monitoringData.tickHistory[i] = monitoringData.tickHistory[i + 1];
            }
            monitoringData.tickHistory.pop();
        }

        // Calculate volatility metrics
        _updateVolatilityMetrics(
            PoolId.unwrap(key.toId()), bytes32(uint256(uint160(liquidationData.protocolAdapter)))
        );

        // Emit monitoring event
        emit TickRangeUpdated(
            PoolId.unwrap(key.toId()),
            bytes32(uint256(uint160(liquidationData.protocolAdapter))),
            currentTick,
            monitoringData.volatilityScore
        );
    }

    // =============================================================================
    // LP POSITION MANAGEMENT FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate optimal lower tick for LP position
     * @param currentTick The current pool tick
     * @param protocolAdapter The protocol adapter identifier
     * @return optimalLowerTick The calculated optimal lower tick
     */
    function _calculateOptimalLowerTick(
        int24 currentTick,
        bytes32 protocolAdapter
    )
        internal
        view
        returns (int24 optimalLowerTick)
    {
        // Get protocol-specific configuration
        ProtocolAdapter memory adapter =
            protocolAdapters[address(uint160(uint256(protocolAdapter)))];

        // Calculate lower bound based on liquidation threshold
        // Typically 10-20% below current price for liquidation scenarios
        int24 tickSpacing = 60; // Standard tick spacing for most pools
        int24 lowerOffset = int24(int256((adapter.liquidationThreshold * 200) / 10_000)); // Convert to tick offset

        optimalLowerTick = currentTick - lowerOffset;

        // Align to tick spacing
        optimalLowerTick = (optimalLowerTick / tickSpacing) * tickSpacing;

        return optimalLowerTick;
    }

    /**
     * @notice Calculate optimal upper tick for LP position
     * @param currentTick The current pool tick
     * @param protocolAdapter The protocol adapter identifier
     * @return optimalUpperTick The calculated optimal upper tick
     */
    function _calculateOptimalUpperTick(
        int24 currentTick,
        bytes32 protocolAdapter
    )
        internal
        view
        returns (int24 optimalUpperTick)
    {
        // Get protocol-specific configuration
        ProtocolAdapter memory adapter =
            protocolAdapters[address(uint160(uint256(protocolAdapter)))];

        // Calculate upper bound for optimal liquidity provision
        // Typically 15-30% above current price
        int24 tickSpacing = 60;
        int24 upperOffset = int24(int256((adapter.liquidationThreshold * 300) / 10_000));

        optimalUpperTick = currentTick + upperOffset;

        // Align to tick spacing
        optimalUpperTick = (optimalUpperTick / tickSpacing) * tickSpacing;

        return optimalUpperTick;
    }

    /**
     * @notice Check if LP position should be rebalanced
     * @param currentPosition Current LP position info
     * @param optimalLowerTick Optimal lower tick
     * @param optimalUpperTick Optimal upper tick
     * @param currentTick Current pool tick
     * @return shouldRebalance True if rebalancing is needed
     */
    function _shouldRebalancePosition(
        LPPositionInfo memory currentPosition,
        int24 optimalLowerTick,
        int24 optimalUpperTick,
        int24 currentTick
    )
        internal
        pure
        returns (bool shouldRebalance)
    {
        // Check if position exists
        if (currentPosition.liquidity == 0) {
            return true; // Need to create initial position
        }

        // Check if current tick is outside position range
        if (currentTick <= currentPosition.lowerTick || currentTick >= currentPosition.upperTick) {
            return true; // Position is out of range
        }

        // Check if optimal range differs significantly from current range
        int24 lowerTickDiff = currentPosition.lowerTick > optimalLowerTick
            ? currentPosition.lowerTick - optimalLowerTick
            : optimalLowerTick - currentPosition.lowerTick;

        int24 upperTickDiff = currentPosition.upperTick > optimalUpperTick
            ? currentPosition.upperTick - optimalUpperTick
            : optimalUpperTick - currentPosition.upperTick;

        // Rebalance if difference is more than 5% of the range
        int24 rangeSize = currentPosition.upperTick - currentPosition.lowerTick;
        int24 threshold = rangeSize / 20; // 5% threshold

        return (lowerTickDiff > threshold || upperTickDiff > threshold);
    }

    /**
     * @notice Execute LP position rebalancing
     * @param key The pool key
     * @param protocolAdapter The protocol adapter identifier
     * @param currentPosition Current position info
     * @param newLowerTick New lower tick
     * @param newUpperTick New upper tick
     * @param delta Balance delta from swap
     */
    function _executePositionRebalancing(
        PoolKey calldata key,
        bytes32 protocolAdapter,
        LPPositionInfo memory currentPosition,
        int24 newLowerTick,
        int24 newUpperTick,
        BalanceDelta delta
    )
        internal
    {
        PoolId poolId = key.toId();

        // Remove existing liquidity if any
        if (currentPosition.liquidity > 0) {
            // Calculate position key for the liquidity to remove
            bytes32 positionKey = Position.calculatePositionKey(
                address(this), currentPosition.lowerTick, currentPosition.upperTick, bytes32(0)
            );

            // Remove liquidity using PoolManager
            (BalanceDelta removeDelta,) = poolManager.modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: currentPosition.lowerTick,
                    tickUpper: currentPosition.upperTick,
                    liquidityDelta: -int256(uint256(currentPosition.liquidity)),
                    salt: bytes32(0)
                }),
                ""
            );
        }

        // Calculate new liquidity amount based on available tokens
        uint128 newLiquidity = _calculateOptimalLiquidity(key, newLowerTick, newUpperTick, delta);

        // Add new liquidity position
        if (newLiquidity > 0) {
            // Add liquidity using PoolManager
            (BalanceDelta addDelta,) = poolManager.modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: newLowerTick,
                    tickUpper: newUpperTick,
                    liquidityDelta: int256(uint256(newLiquidity)),
                    salt: bytes32(0)
                }),
                ""
            );
        }

        // Update position tracking
        lpPositions[PoolId.unwrap(poolId)][protocolAdapter] = LPPositionInfo({
            liquidity: newLiquidity,
            lowerTick: newLowerTick,
            upperTick: newUpperTick,
            lastUpdateTimestamp: block.timestamp,
            feesEarned0: 0, // Reset fees tracking
            feesEarned1: 0
        });

        // Emit rebalancing event
        emit PositionRebalanced(
            key,
            address(this), // Hook contract as position owner
            currentPosition.lowerTick,
            currentPosition.upperTick,
            newLowerTick,
            newUpperTick
        );
    }

    /**
     * @notice Calculate optimal liquidity for new position
     * @param key The pool key
     * @param lowerTick Lower tick of position
     * @param upperTick Upper tick of position
     * @param delta Available token amounts
     * @return liquidity Calculated liquidity amount
     */
    function _calculateOptimalLiquidity(
        PoolKey calldata key,
        int24 lowerTick,
        int24 upperTick,
        BalanceDelta delta
    )
        internal
        view
        returns (uint128 liquidity)
    {
        // Get current pool price
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, key.toId());

        // Convert ticks to sqrt price ratios
        uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(lowerTick);
        uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(upperTick);

        // Get absolute amounts from delta
        uint256 amount0 = delta.amount0() < 0
            ? uint256(uint128(-delta.amount0()))
            : uint256(uint128(delta.amount0()));
        uint256 amount1 = delta.amount1() < 0
            ? uint256(uint128(-delta.amount1()))
            : uint256(uint128(delta.amount1()));

        // Calculate liquidity using LiquidityAmounts library
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1
        );

        return liquidity;
    }

    /**
     * @notice Update volatility metrics for tick monitoring
     * @param poolId The pool identifier
     * @param protocolAdapter The protocol adapter identifier
     */
    function _updateVolatilityMetrics(bytes32 poolId, bytes32 protocolAdapter) internal {
        TickMonitoringData storage data = tickMonitoring[poolId][protocolAdapter];

        if (data.tickHistory.length < 2) {
            return; // Need at least 2 data points
        }

        // Calculate average tick movement
        uint256 totalMovement = 0;
        for (uint256 i = 1; i < data.tickHistory.length; i++) {
            int24 movement = data.tickHistory[i] > data.tickHistory[i - 1]
                ? data.tickHistory[i] - data.tickHistory[i - 1]
                : data.tickHistory[i - 1] - data.tickHistory[i];
            totalMovement += uint256(int256(movement));
        }

        data.averageTickMovement = totalMovement / (data.tickHistory.length - 1);

        // Simple volatility score (0-100)
        data.volatilityScore =
            data.averageTickMovement > 1000 ? 100 : (data.averageTickMovement * 100) / 1000;
    }

    // =============================================================================
    // LIQUIDATION FUNCTIONS
    // =============================================================================

    /**
     * @notice Check if a liquidation should be executed
     * @param liquidationData The liquidation parameters
     * @return shouldLiquidate True if liquidation should proceed
     */
    function _shouldExecuteLiquidation(LiquidationData memory liquidationData)
        internal
        view
        returns (bool shouldLiquidate)
    {
        // Verify protocol adapter is enabled
        ProtocolAdapter memory adapter = protocolAdapters[liquidationData.protocolAdapter];
        if (!adapter.enabled) {
            return false;
        }

        // Check health factor based on protocol
        uint256 healthFactor = _getHealthFactor(liquidationData);

        return healthFactor < adapter.liquidationThreshold;
    }

    /**
     * @notice Execute liquidation for undercollateralized position
     * @param sender The liquidator address
     * @param key The pool key
     * @param params The swap parameters
     * @param liquidationData The liquidation parameters
     */
    function _executeLiquidation(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        LiquidationData memory liquidationData
    )
        internal
    {
        // Verify liquidator authorization
        if (!authorizedLiquidators[sender]) {
            revert UnauthorizedLiquidator();
        }

        // Execute protocol-specific liquidation
        if (liquidationData.protocolAdapter == address(0)) {
            revert InvalidProtocolAdapter();
        }

        // Call the appropriate protocol liquidation function
        _callProtocolLiquidation(liquidationData);

        emit LiquidationExecuted(
            sender,
            liquidationData.borrower,
            liquidationData.collateralAsset,
            liquidationData.debtAsset,
            0, // Will be updated with actual amounts
            liquidationData.debtToCover,
            0 // Will be calculated
        );
    }

    /**
     * @notice Get health factor for a borrower from the lending protocol
     * @param liquidationData The liquidation parameters
     * @return healthFactor The current health factor (scaled by 1e18)
     */
    function _getHealthFactor(LiquidationData memory liquidationData)
        internal
        view
        returns (uint256 healthFactor)
    {
        ProtocolAdapter memory adapter = protocolAdapters[liquidationData.protocolAdapter];

        // Check if this is an Aave V3 protocol
        if (_isAaveV3Protocol(adapter.adapterAddress)) {
            return _getAaveV3HealthFactor(adapter.adapterAddress, liquidationData.borrower);
        }
        // Check if this is a Compound V3 protocol
        else if (_isCompoundV3Protocol(adapter.adapterAddress)) {
            return _getCompoundV3HealthFactor(adapter.adapterAddress, liquidationData.borrower);
        }

        // Default fallback
        return type(uint256).max;
    }

    /**
     * @notice Get health factor from Aave V3 protocol
     * @param poolAddress The Aave V3 pool address
     * @param user The user address
     * @return healthFactor The health factor from Aave V3
     */
    function _getAaveV3HealthFactor(
        address poolAddress,
        address user
    )
        internal
        view
        returns (uint256 healthFactor)
    {
        IAaveV3Pool pool = IAaveV3Pool(poolAddress);

        (,,,,, uint256 aaveHealthFactor) = pool.getUserAccountData(user);

        return aaveHealthFactor;
    }

    /**
     * @notice Get health factor equivalent from Compound V3 protocol
     * @param cometAddress The Compound V3 Comet address
     * @param user The user address
     * @return healthFactor The calculated health factor equivalent
     */
    function _getCompoundV3HealthFactor(
        address cometAddress,
        address user
    )
        internal
        view
        returns (uint256 healthFactor)
    {
        ICompoundV3Comet comet = ICompoundV3Comet(cometAddress);

        // Check if user is liquidatable (underwater)
        if (comet.isLiquidatable(user)) {
            return 0.95e18; // Below liquidation threshold
        }

        // Check if borrow is collateralized
        if (!comet.isBorrowCollateralized(user)) {
            return 0.99e18; // Close to liquidation
        }

        // If not liquidatable and properly collateralized, assume healthy
        return 1.2e18; // Above liquidation threshold
    }

    /**
     * @notice Check if an address is an Aave V3 protocol
     * @param protocolAddress The protocol address to check
     * @return isAave True if it's an Aave V3 protocol
     */
    function _isAaveV3Protocol(address protocolAddress) internal view returns (bool isAave) {
        // Try to call a function specific to Aave V3
        try IAaveV3Pool(protocolAddress).MAX_NUMBER_RESERVES() returns (uint16) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Check if an address is a Compound V3 protocol
     * @param protocolAddress The protocol address to check
     * @return isCompound True if it's a Compound V3 protocol
     */
    function _isCompoundV3Protocol(address protocolAddress)
        internal
        view
        returns (bool isCompound)
    {
        // Try to call a function specific to Compound V3
        try ICompoundV3Comet(protocolAddress).baseToken() returns (address) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Call the appropriate protocol liquidation function
     * @param liquidationData The liquidation parameters
     */
    function _callProtocolLiquidation(LiquidationData memory liquidationData) internal {
        ProtocolAdapter memory adapter = protocolAdapters[liquidationData.protocolAdapter];

        // Execute Aave V3 liquidation
        if (_isAaveV3Protocol(adapter.adapterAddress)) {
            _executeAaveV3Liquidation(adapter.adapterAddress, liquidationData);
        }
        // Execute Compound V3 liquidation (absorption)
        else if (_isCompoundV3Protocol(adapter.adapterAddress)) {
            _executeCompoundV3Liquidation(adapter.adapterAddress, liquidationData);
        } else {
            revert InvalidProtocolAdapter();
        }
    }

    /**
     * @notice Execute Aave V3 liquidation
     * @param poolAddress The Aave V3 pool address
     * @param liquidationData The liquidation parameters
     */
    function _executeAaveV3Liquidation(
        address poolAddress,
        LiquidationData memory liquidationData
    )
        internal
    {
        IAaveV3Pool pool = IAaveV3Pool(poolAddress);

        // Execute the liquidation call
        pool.liquidationCall(
            liquidationData.collateralAsset,
            liquidationData.debtAsset,
            liquidationData.borrower,
            liquidationData.debtToCover,
            liquidationData.receiveAToken
        );
    }

    /**
     * @notice Execute Compound V3 liquidation (absorption)
     * @param cometAddress The Compound V3 Comet address
     * @param liquidationData The liquidation parameters
     */
    function _executeCompoundV3Liquidation(
        address cometAddress,
        LiquidationData memory liquidationData
    )
        internal
    {
        ICompoundV3Comet comet = ICompoundV3Comet(cometAddress);

        // Create array with single account to absorb
        address[] memory accounts = new address[](1);
        accounts[0] = liquidationData.borrower;

        // Absorb the underwater account
        comet.absorb(msg.sender, accounts);

        // Optionally buy collateral if specified
        if (liquidationData.collateralAsset != address(0) && liquidationData.debtToCover > 0) {
            comet.buyCollateral(
                liquidationData.collateralAsset,
                0, // minAmount - could be calculated based on slippage tolerance
                liquidationData.debtToCover,
                msg.sender
            );
        }
    }

    // =============================================================================
    // REBALANCING FUNCTIONS
    // =============================================================================

    /**
     * @notice Check if a position should be rebalanced
     * @param key The pool key
     * @param position The position data
     * @return shouldRebalance True if rebalancing is needed
     */
    function _shouldRebalancePosition(
        PoolKey calldata key,
        RebalanceData storage position
    )
        internal
        view
        returns (bool shouldRebalance)
    {
        // Get current tick from pool
        (, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, key.toId());

        // Check if current tick is outside the position range
        if (currentTick <= position.tickLower || currentTick >= position.tickUpper) {
            return true;
        }

        // Check if position is close to range boundaries (within 10% of range)
        int24 rangeWidth = position.tickUpper - position.tickLower;
        int24 threshold = rangeWidth / 10;

        // Rebalance if within threshold of boundaries
        if (
            currentTick - position.tickLower <= threshold
                || position.tickUpper - currentTick <= threshold
        ) {
            return true;
        }

        return false;
    }

    /**
     * @notice Rebalance a liquidity position
     * @param key The pool key
     * @param position The position data
     */
    function _rebalancePosition(PoolKey calldata key, RebalanceData storage position) internal {
        // Calculate optimal new tick range
        (int24 newTickLower, int24 newTickUpper) = _calculateOptimalRange(key, position);

        // Validate new tick range
        if (newTickLower >= newTickUpper) {
            revert InvalidTickRange();
        }

        // Store old ticks for event
        int24 oldTickLower = position.tickLower;
        int24 oldTickUpper = position.tickUpper;

        // Update position data
        position.tickLower = newTickLower;
        position.tickUpper = newTickUpper;

        emit PositionRebalanced(
            key, position.positionOwner, oldTickLower, oldTickUpper, newTickLower, newTickUpper
        );
    }

    /**
     * @notice Calculate optimal tick range for rebalancing
     * @param key The pool key
     * @param position The position data
     * @return newTickLower The new lower tick
     * @return newTickUpper The new upper tick
     */
    function _calculateOptimalRange(
        PoolKey calldata key,
        RebalanceData storage position
    )
        internal
        view
        returns (int24 newTickLower, int24 newTickUpper)
    {
        // Get current tick from pool
        (, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, key.toId());

        // Get volatility metric for dynamic range sizing
        uint256 volatility = _getVolatilityMetric(key);

        // Calculate base range based on volatility
        // Higher volatility = wider range to reduce rebalancing frequency
        int24 baseRange = int24(uint24(volatility * 100)); // Scale volatility to tick range

        // Ensure minimum and maximum range bounds
        int24 minRange = 200; // Minimum range in ticks
        int24 maxRange = 2000; // Maximum range in ticks

        if (baseRange < minRange) baseRange = minRange;
        if (baseRange > maxRange) baseRange = maxRange;

        // Calculate symmetric range around current tick
        int24 tickSpacing = 60; // Standard tick spacing for most pools

        newTickLower = currentTick - baseRange;
        newTickUpper = currentTick + baseRange;

        // Align to tick spacing
        newTickLower = (newTickLower / tickSpacing) * tickSpacing;
        newTickUpper = (newTickUpper / tickSpacing) * tickSpacing;

        // Ensure ticks are within valid bounds
        if (newTickLower < TickMath.MIN_TICK) newTickLower = TickMath.MIN_TICK;
        if (newTickUpper > TickMath.MAX_TICK) newTickUpper = TickMath.MAX_TICK;
    }

    /**
     * @notice Get volatility metric for a pool
     * @param key The pool key
     * @return volatility The volatility metric (0-100)
     */
    function _getVolatilityMetric(PoolKey calldata key)
        internal
        view
        returns (uint256 volatility)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());

        // Try to get volatility from different protocol adapters
        // Use the highest volatility found across all adapters
        uint256 maxVolatility = 0;
        bool hasData = false;

        // Check Aave adapter data if available
        bytes32 aaveAdapter = keccak256("AAVE_V3");
        TickMonitoringData storage aaveData = tickMonitoring[poolId][aaveAdapter];
        if (aaveData.tickHistory.length >= 10) {
            uint256 aaveVolatility = _calculateVolatilityFromTicks(aaveData);
            if (aaveVolatility > maxVolatility) {
                maxVolatility = aaveVolatility;
            }
            hasData = true;
        }

        // Check Compound adapter data if available
        bytes32 compoundAdapter = keccak256("COMPOUND_V3");
        TickMonitoringData storage compoundData = tickMonitoring[poolId][compoundAdapter];
        if (compoundData.tickHistory.length >= 10) {
            uint256 compoundVolatility = _calculateVolatilityFromTicks(compoundData);
            if (compoundVolatility > maxVolatility) {
                maxVolatility = compoundVolatility;
            }
            hasData = true;
        }

        // If we have historical data, use it; otherwise fall back to current price analysis
        if (hasData) {
            return maxVolatility;
        }

        // Fallback: Calculate volatility from current pool state
        return _calculateCurrentPoolVolatility(key);
    }

    /**
     * @notice Calculate volatility from tick history using standard deviation
     * @param data The tick monitoring data
     * @return volatility The calculated volatility (0-100)
     */
    function _calculateVolatilityFromTicks(TickMonitoringData storage data)
        internal
        view
        returns (uint256 volatility)
    {
        if (data.tickHistory.length < 10) {
            return 50; // Default moderate volatility
        }

        // Calculate the mean of recent tick movements
        uint256 recentPeriod = data.tickHistory.length > 50 ? 50 : data.tickHistory.length;
        int256 totalMovement = 0;
        uint256 startIndex = data.tickHistory.length - recentPeriod;

        for (uint256 i = startIndex + 1; i < data.tickHistory.length; i++) {
            int24 movement = data.tickHistory[i] - data.tickHistory[i - 1];
            totalMovement += movement;
        }

        int256 meanMovement = totalMovement / int256(recentPeriod - 1);

        // Calculate variance (sum of squared deviations from mean)
        uint256 variance = 0;
        for (uint256 i = startIndex + 1; i < data.tickHistory.length; i++) {
            int24 movement = data.tickHistory[i] - data.tickHistory[i - 1];
            int256 deviation = movement - meanMovement;
            variance += uint256(deviation * deviation);
        }

        variance = variance / (recentPeriod - 1);

        // Calculate standard deviation (square root of variance)
        uint256 stdDev = _sqrt(variance);

        // Convert to volatility score (0-100)
        // Higher tick standard deviation = higher volatility
        // Scale: 0-200 tick stddev maps to 0-100 volatility
        if (stdDev > 200) {
            return 100;
        }

        return (stdDev * 100) / 200;
    }

    /**
     * @notice Calculate volatility from current pool state when no history is available
     * @param key The pool key
     * @return volatility The calculated volatility (0-100)
     */
    function _calculateCurrentPoolVolatility(PoolKey calldata key)
        internal
        view
        returns (uint256 volatility)
    {
        // Get current pool state
        (uint160 sqrtPriceX96, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, key.toId());

        // Estimate volatility based on pool fee tier and current tick
        // Higher fee pools typically indicate higher volatility assets
        uint24 fee = key.fee;

        // Base volatility from fee tier
        uint256 baseVolatility;
        if (fee >= 10_000) {
            // 1% fee
            baseVolatility = 80; // High volatility
        } else if (fee >= 3000) {
            // 0.3% fee
            baseVolatility = 50; // Medium volatility
        } else if (fee >= 500) {
            // 0.05% fee
            baseVolatility = 30; // Low-medium volatility
        } else {
            // 0.01% fee
            baseVolatility = 20; // Low volatility
        }

        // Adjust based on how far current tick is from typical ranges
        // Extreme ticks might indicate higher volatility
        int24 absCurrentTick = currentTick < 0 ? -currentTick : currentTick;
        if (absCurrentTick > 100_000) {
            baseVolatility = (baseVolatility * 120) / 100; // +20%
        } else if (absCurrentTick > 50_000) {
            baseVolatility = (baseVolatility * 110) / 100; // +10%
        }

        // Cap at 100
        return baseVolatility > 100 ? 100 : baseVolatility;
    }

    /**
     * @notice Calculate integer square root using Newton's method
     * @param x The number to find square root of
     * @return result The square root
     */
    function _sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) {
            return 0;
        }

        // Initial guess
        result = x;
        uint256 k = (x / 2) + 1;

        // Newton's method iteration
        while (k < result) {
            result = k;
            k = (x / k + k) / 2;
        }
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    /**
     * @notice Generate position ID from pool key and owner
     * @param key The pool key
     * @param owner The position owner
     * @return positionId The unique position identifier
     */
    function _getPositionId(PoolKey calldata key, address owner) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(key.currency0, key.currency1, key.fee, owner));
    }

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    /**
     * @notice Add or update a protocol adapter
     * @param protocol The protocol address
     * @param adapter The adapter address
     * @param enabled Whether the adapter is enabled
     * @param liquidationThreshold The liquidation threshold for this protocol
     */
    function setProtocolAdapter(
        address protocol,
        address adapter,
        bool enabled,
        uint256 liquidationThreshold
    )
        external
        onlyOwner
    {
        protocolAdapters[protocol] = ProtocolAdapter({
            adapterAddress: adapter,
            enabled: enabled,
            liquidationThreshold: liquidationThreshold
        });

        emit ProtocolAdapterUpdated(protocol, adapter, enabled);
    }

    /**
     * @notice Set liquidator authorization
     * @param liquidator The liquidator address
     * @param authorized Whether the liquidator is authorized
     */
    function setLiquidatorAuthorization(address liquidator, bool authorized) external onlyOwner {
        authorizedLiquidators[liquidator] = authorized;
    }

    /**
     * @notice Enable auto-rebalancing for a position
     * @param key The pool key
     * @param tickLower The lower tick
     * @param tickUpper The upper tick
     * @param liquidity The liquidity amount
     */
    function enableAutoRebalance(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        external
    {
        bytes32 positionId = _getPositionId(key, msg.sender);

        positionData[positionId] = RebalanceData({
            positionOwner: msg.sender,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            autoRebalanceEnabled: true
        });
    }

    /**
     * @notice Disable auto-rebalancing for a position
     * @param key The pool key
     */
    function disableAutoRebalance(PoolKey calldata key) external {
        bytes32 positionId = _getPositionId(key, msg.sender);
        positionData[positionId].autoRebalanceEnabled = false;
    }

    /**
     * @notice Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Emergency unpause function
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @notice Get position data for a given pool and owner
     * @param key The pool key
     * @param owner The position owner
     * @return position The position data
     */
    function getPositionData(
        PoolKey calldata key,
        address owner
    )
        external
        view
        returns (RebalanceData memory position)
    {
        bytes32 positionId = _getPositionId(key, owner);
        return positionData[positionId];
    }

    /**
     * @notice Check if a liquidator is authorized
     * @param liquidator The liquidator address
     * @return authorized True if authorized
     */
    function isLiquidatorAuthorized(address liquidator) external view returns (bool authorized) {
        return authorizedLiquidators[liquidator];
    }

    /**
     * @notice Get protocol adapter information
     * @param protocol The protocol address
     * @return adapter The adapter information
     */
    function getProtocolAdapter(address protocol)
        external
        view
        returns (ProtocolAdapter memory adapter)
    {
        return protocolAdapters[protocol];
    }

    /// @notice Public getter for volatility metric (for testing purposes)
    function getVolatilityMetric(PoolKey calldata key) external view returns (uint256) {
        return _getVolatilityMetric(key);
    }

    /**
     * @notice Returns the hook permissions for this contract
     * @return permissions The hook permissions struct
     */
    function beforeInitialize(
        address, /* sender */
        PoolKey calldata, /* key */
        uint160 /* sqrtPriceX96 */
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(
        address, /* sender */
        PoolKey calldata, /* key */
        uint160, /* sqrtPriceX96 */
        int24 /* tick */
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterInitialize.selector;
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
