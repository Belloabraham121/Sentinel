// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title HookMiner
 * @notice Utility for mining hook addresses with specific flags
 */
library HookMiner {
    /**
     * @notice Find a salt that produces a hook address with the desired flags
     * @param deployer The address that will deploy the hook
     * @param flags The desired hook flags
     * @param creationCode The creation code of the hook contract
     * @param constructorArgs The encoded constructor arguments
     * @return hookAddress The computed hook address
     * @return salt The salt that produces the desired address
     */
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        // Simple implementation that tries different salts
        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(
                deployer,
                salt,
                creationCode,
                constructorArgs
            );

            // Check if the address has the desired flags in the lower 160 bits
            if (uint160(hookAddress) & flags == flags) {
                return (hookAddress, salt);
            }
        }

        revert("HookMiner: Could not find valid salt");
    }

    /**
     * @notice Compute the address of a contract deployed with CREATE2
     * @param deployer The address that will deploy the contract
     * @param salt The salt for CREATE2
     * @param creationCode The creation code of the contract
     * @param constructorArgs The encoded constructor arguments
     * @return The computed address
     */
    function computeAddress(
        address deployer,
        bytes32 salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer,
                salt,
                keccak256(abi.encodePacked(creationCode, constructorArgs))
            )
        );

        return address(uint160(uint256(hash)));
    }
}
