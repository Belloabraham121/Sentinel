// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console } from "forge-std/Script.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { HookMiner } from "../src/utils/HookMiner.sol";
import { LendingLiquidityGuardianHook } from "../src/LendingLiquidityGuardianHook.sol";

contract DeployLendingLiquidityGuardianHook is Script {
    // Network-specific addresses
    struct NetworkConfig {
        address poolManager;
        address aaveV3Pool;
        address aaveV3Oracle;
        address compoundV3Usdc;
        address compoundV3Weth;
    }

    // Mainnet configuration
    NetworkConfig mainnetConfig = NetworkConfig({
        poolManager: 0x0000000000000000000000000000000000000000, // To be updated with actual V4 deployment
        aaveV3Pool: 0x87870bace7f90f81e72b01b9De3656c4C2427C4E,
        aaveV3Oracle: 0x54586bE62E3c3580375aE3723C145253060Ca0C2,
        compoundV3Usdc: 0xc3d688B66703497DAA19211EEdff47f25384cdc3,
        compoundV3Weth: 0xA17581A9E3356d9A858b789D68B4d866e593aE94
    });

    // Sepolia testnet configuration
    NetworkConfig sepoliaConfig = NetworkConfig({
        poolManager: 0x0000000000000000000000000000000000000000, // To be updated with testnet deployment
        aaveV3Pool: 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951,
        aaveV3Oracle: 0x2da88497588bf89281816106C7259e31AF45a663,
        compoundV3Usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
        compoundV3Weth: address(0) // Not available on Sepolia
     });

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying LendingLiquidityGuardianHook with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        // Get network configuration
        NetworkConfig memory config = getNetworkConfig();

        require(
            config.poolManager != address(0), "PoolManager address not configured for this network"
        );

        vm.startBroadcast(deployerPrivateKey);

        // Mine a salt that will produce a hook address with the correct flags
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        console.log("Mining hook address with flags:", flags);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer,
            flags,
            type(LendingLiquidityGuardianHook).creationCode,
            abi.encode(config.poolManager)
        );

        console.log("Mined hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        // Deploy the hook to the pre-mined address
        LendingLiquidityGuardianHook hook =
            new LendingLiquidityGuardianHook{ salt: salt }(IPoolManager(config.poolManager));

        require(address(hook) == hookAddress, "Hook address mismatch");

        console.log("LendingLiquidityGuardianHook deployed at:", address(hook));

        // Configure protocol adapters
        _configureProtocolAdapters(hook, config);

        // Set up initial authorized liquidators (deployer by default)
        hook.setLiquidatorAuthorization(deployer, true);
        console.log("Added deployer as authorized liquidator:", deployer);

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary(address(hook), config);
    }

    function getNetworkConfig() internal view returns (NetworkConfig memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            return mainnetConfig;
        } else if (chainId == 11_155_111) {
            return sepoliaConfig;
        } else {
            revert("Unsupported network");
        }
    }

    function _configureProtocolAdapters(
        LendingLiquidityGuardianHook hook,
        NetworkConfig memory config
    )
        internal
    {
        console.log("Configuring protocol adapters...");

        // Configure Aave V3
        if (config.aaveV3Pool != address(0)) {
            hook.setProtocolAdapter(
                config.aaveV3Pool,
                config.aaveV3Oracle,
                true,
                1.05e18 // 105% liquidation threshold
            );
            console.log("Configured Aave V3 adapter:", config.aaveV3Pool);
        }

        // Configure Compound V3 USDC
        if (config.compoundV3Usdc != address(0)) {
            hook.setProtocolAdapter(
                config.compoundV3Usdc,
                address(0), // Compound uses internal oracle
                true,
                1.05e18 // 105% liquidation threshold
            );
            console.log("Configured Compound V3 USDC adapter:", config.compoundV3Usdc);
        }

        // Configure Compound V3 WETH (if available)
        if (config.compoundV3Weth != address(0)) {
            hook.setProtocolAdapter(
                config.compoundV3Weth,
                address(0),
                true,
                1.05e18 // 105% liquidation threshold
            );
            console.log("Configured Compound V3 WETH adapter:", config.compoundV3Weth);
        }
    }

    function _logDeploymentSummary(
        address hookAddress,
        NetworkConfig memory config
    )
        internal
        view
    {
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", getNetworkName());
        console.log("Hook Address:", hookAddress);
        console.log("Pool Manager:", config.poolManager);
        console.log("Aave V3 Pool:", config.aaveV3Pool);
        console.log("Aave V3 Oracle:", config.aaveV3Oracle);
        console.log("Compound V3 USDC:", config.compoundV3Usdc);
        if (config.compoundV3Weth != address(0)) {
            console.log("Compound V3 WETH:", config.compoundV3Weth);
        }
        console.log("========================\n");
    }

    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            return "Ethereum Mainnet";
        } else if (chainId == 11_155_111) {
            return "Sepolia Testnet";
        } else {
            return "Unknown Network";
        }
    }

    // Helper function for testing deployment locally
    function deployLocal(address poolManager) external returns (address) {
        // Mine a salt for local deployment
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(LendingLiquidityGuardianHook).creationCode,
            abi.encode(poolManager)
        );

        // Deploy the hook
        LendingLiquidityGuardianHook hook =
            new LendingLiquidityGuardianHook{ salt: salt }(IPoolManager(poolManager));

        require(address(hook) == hookAddress, "Hook address mismatch");

        return address(hook);
    }
}
