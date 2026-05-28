// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

contract RewardTokensManager is Ownable { // Main contract for managing reward tokens, responsible for creating the Uniswap V4 pool and handling reward distribution
    using PoolIdLibrary for PoolKey; // Library for working with PoolKey and PoolId types

    uint24 public constant FEE_TIER = 3000; // Fee tier for the Uniswap V4 pool (0.3% fee)
    int24 public constant TICK_SPACING = 60; // Tick spacing for the pool, paired with the 0.3% fee tier
    address public constant HOOKS = address(0);

    IPoolManager public immutable poolManager; // Interface for interacting with the Uniswap V4 pool manager, used to create and manage liquidity pools
    IPositionManager public immutable positionManager; // Interface for managing liquidity positions in the Uniswap V4 pool, used to add/remove liquidity and collect fees
    address public immutable pnpToken; // Address of the PNPToken, one of the two reward tokens that will be traded in the Uniswap V4 pool
    address public immutable fnbToken; // Addresses of the two reward tokens (PNPToken and FNBToken) that will be traded in the Uniswap V4 pool

    address public currency0;
    address public currency1;

    mapping(bytes32 => bool) public createdPools; // Mapping to track which pools have been created by this contract, using the pool ID as the key and a boolean to indicate if it has been created

    event PoolCreated( 
        bytes32 poolId,
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        uint160 sqrtPriceX96
    );

    constructor( // Constructor for the RewardTokensManager contract, initializes the pool manager, position manager, and token addresses, and determines the canonical order of the two tokens based on their addresses
        address _poolManager,
        address _positionManager,
        address _pnpToken,
        address _fnbToken
    ) Ownable(msg.sender) { // Initialize the Ownable contract with the deployer as the owner
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager);
        pnpToken = _pnpToken;
        fnbToken = _fnbToken;

        // Determine the canonical order of the two tokens based on their addresses, ensuring that currency0 is always the token with the lower address and currency1 is the token with the higher address. This is important for consistency in how the Uniswap V4 pool identifies the two tokens and calculates prices.
        if (_pnpToken < _fnbToken) {
            currency0 = _pnpToken;
            currency1 = _fnbToken;
        } else {
            currency0 = _fnbToken;
            currency1 = _pnpToken;
        }
    }

    function _poolKey() internal view returns (PoolKey memory) { // Internal function to construct the PoolKey struct for the Uniswap V4 pool, which includes the two currencies, fee tier, tick spacing, and hooks address. This key is used to identify the pool when creating it and interacting with it through the pool manager and position manager.
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: FEE_TIER,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOKS)
        });
    }

    function getCanonicalCurrencies() public view returns (address, address) { // Public function to return the canonical order of the two reward token addresses, ensuring that users and external contracts can easily determine which token is currency0 and which is currency1 when interacting with the Uniswap V4 pool
        return (currency0, currency1);
    }

    function getPoolId() public view returns (bytes32) { // Public function to return the pool ID for the Uniswap V4 pool that this contract manages, which is derived from the PoolKey. This ID is used to identify the pool when interacting with it through the pool manager and position manager, and can be used by external contracts to query information about the pool or add/remove liquidity.
        return PoolId.unwrap(_poolKey().toId());
    }

    function getTargetTick() public pure returns (int24) {
        
        // price = currency1/currency0 = 1.0001^tick. Derive the tick for that ratio and align to spacing 60.
        return 23040;
    }

    function createPool(uint160 sqrtPriceX96) external onlyOwner returns (bytes32 poolId) {
        // Create the Uniswap V4 pool for the two reward tokens with the specified initial price (sqrtPriceX96). This function can only be called by the owner of the contract (e.g., a governance contract or admin) to ensure that the pool is created in a controlled manner. The function constructs the PoolKey, calls the pool manager to initialize the pool, and emits an event with the details of the created pool.
        PoolKey memory key = _poolKey();
        poolManager.initialize(key, sqrtPriceX96);

        poolId = PoolId.unwrap(key.toId());
        createdPools[poolId] = true;

        emit PoolCreated(poolId, currency0, currency1, FEE_TIER, TICK_SPACING, HOOKS, sqrtPriceX96); // Emit an event to log the creation of the new pool. 
}
} 

