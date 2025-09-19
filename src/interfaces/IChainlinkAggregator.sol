// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IChainlinkAggregator
 * @notice Interface for Chainlink price feed aggregators
 * @dev This interface provides access to Chainlink price feeds for real-time asset pricing
 */
interface IChainlinkAggregator {
    /**
     * @notice Returns the latest price data
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID of the round in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /**
     * @notice Returns the latest answer
     * @return The latest answer
     */
    function latestAnswer() external view returns (int256);

    /**
     * @notice Returns the latest timestamp
     * @return The latest timestamp
     */
    function latestTimestamp() external view returns (uint256);

    /**
     * @notice Returns the latest round
     * @return The latest round
     */
    function latestRound() external view returns (uint256);

    /**
     * @notice Returns the answer for a specific round
     * @param roundId The round ID
     * @return The answer for the round
     */
    function getAnswer(uint256 roundId) external view returns (int256);

    /**
     * @notice Returns the timestamp for a specific round
     * @param roundId The round ID
     * @return The timestamp for the round
     */
    function getTimestamp(uint256 roundId) external view returns (uint256);

    /**
     * @notice Returns the round data for a specific round
     * @param roundId The round ID
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID of the round in which the answer was computed
     */
    function getRoundData(
        uint80 roundId
    )
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /**
     * @notice Returns the number of decimals in the response
     * @return The number of decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the description of the aggregator
     * @return The description string
     */
    function description() external view returns (string memory);

    /**
     * @notice Returns the version of the aggregator
     * @return The version
     */
    function version() external view returns (uint256);

    /**
     * @notice Returns the type and version of the aggregator
     * @return The type and version string
     */
    function typeAndVersion() external pure returns (string memory);
}

/**
 * @title IChainlinkFeedRegistry
 * @notice Interface for Chainlink Feed Registry
 * @dev Provides access to multiple price feeds through a single contract
 */
interface IChainlinkFeedRegistry {
    /**
     * @notice Returns the latest round data for a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID of the round in which the answer was computed
     */
    function latestRoundData(
        address base,
        address quote
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /**
     * @notice Returns the round data for a specific round of a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @param roundId The round ID
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt Timestamp of when the round started
     * @return updatedAt Timestamp of when the round was updated
     * @return answeredInRound The round ID of the round in which the answer was computed
     */
    function getRoundData(
        address base,
        address quote,
        uint80 roundId
    )
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /**
     * @notice Returns the number of decimals for a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @return The number of decimals
     */
    function decimals(
        address base,
        address quote
    ) external view returns (uint8);

    /**
     * @notice Returns the description for a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @return The description string
     */
    function description(
        address base,
        address quote
    ) external view returns (string memory);

    /**
     * @notice Returns the version for a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @return The version
     */
    function version(
        address base,
        address quote
    ) external view returns (uint256);

    /**
     * @notice Returns the aggregator address for a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @return The aggregator address
     */
    function getFeed(
        address base,
        address quote
    ) external view returns (IChainlinkAggregator);

    /**
     * @notice Returns whether a feed exists for a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @return Whether the feed exists
     */
    function isFeedEnabled(
        address base,
        address quote
    ) external view returns (bool);

    /**
     * @notice Returns the previous round ID for a given base/quote pair and round ID
     * @param base The base asset address
     * @param quote The quote asset address
     * @param roundId The round ID
     * @return The previous round ID
     */
    function getPreviousRoundId(
        address base,
        address quote,
        uint80 roundId
    ) external view returns (uint80);

    /**
     * @notice Returns the next round ID for a given base/quote pair and round ID
     * @param base The base asset address
     * @param quote The quote asset address
     * @param roundId The round ID
     * @return The next round ID
     */
    function getNextRoundId(
        address base,
        address quote,
        uint80 roundId
    ) external view returns (uint80);

    /**
     * @notice Returns the phase for a given base/quote pair and round ID
     * @param base The base asset address
     * @param quote The quote asset address
     * @param roundId The round ID
     * @return The phase
     */
    function getPhase(
        address base,
        address quote,
        uint80 roundId
    ) external view returns (uint16);

    /**
     * @notice Returns the round ID at a given phase for a base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @param phaseId The phase ID
     * @return The round ID
     */
    function getRoundIdByPhase(
        address base,
        address quote,
        uint16 phaseId
    ) external view returns (uint80);

    /**
     * @notice Returns the phase range for a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @return startingRoundId The starting round ID
     * @return endingRoundId The ending round ID
     */
    function getPhaseRange(
        address base,
        address quote
    ) external view returns (uint80 startingRoundId, uint80 endingRoundId);

    /**
     * @notice Returns the current phase ID for a given base/quote pair
     * @param base The base asset address
     * @param quote The quote asset address
     * @return The current phase ID
     */
    function getCurrentPhaseId(
        address base,
        address quote
    ) external view returns (uint16);
}
