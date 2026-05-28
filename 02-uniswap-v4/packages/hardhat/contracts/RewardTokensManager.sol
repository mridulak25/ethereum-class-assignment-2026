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
import { Permit2Forwarder } from "@uniswap/v4-periphery/src/base/Permit2Forwarder.sol";

contract RewardTokensManager is Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint24 public constant FEE_TIER = 3000;
    int24 public constant TICK_SPACING = 60;
    address public constant HOOKS = address(0);

    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    address public immutable pnpToken;
    address public immutable fnbToken;

    address public currency0;
    address public currency1;

    mapping(bytes32 => bool) public createdPools;

    event PoolCreated(
        bytes32 poolId,
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        uint160 sqrtPriceX96
    );

    event LiquidityMinted(
        bytes32 poolId,
        uint256 positionId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    );

    error InvalidAmount();
    error InvalidTickRange();
    error PoolNotCreated();
    error TickRangeDoesNotCoverAssignmentPrice();

    constructor(
        address _poolManager,
        address _positionManager,
        address _pnpToken,
        address _fnbToken
    ) Ownable(msg.sender) { 
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager);
        pnpToken = _pnpToken;
        fnbToken = _fnbToken;

        if (_pnpToken < _fnbToken) {
            currency0 = _pnpToken;
            currency1 = _fnbToken;
        } else {
            currency0 = _fnbToken;
            currency1 = _pnpToken;
        }
    }

    function _poolKey() internal view returns (PoolKey memory) { // Helper function to construct the PoolKey struct based on the contract's configured currencies, fee tier, tick spacing, and hooks address. This is used for pool creation and interaction with the PoolManager.
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: FEE_TIER,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOKS)
        });
    }

    function getCanonicalCurrencies() public view returns (address, address) { // Public function to retrieve the canonical currency addresses (currency0 and currency1) that this contract is configured to use for the Uniswap V4 pool. This can be used by external callers to know which tokens are being managed by this contract.
        return (currency0, currency1);
    }

    function getPoolId() public view returns (bytes32) {
        return PoolId.unwrap(_poolKey().toId());
    }

    function getTargetTick() public pure returns (int24) {  // This function returns the target tick that the liquidity position covers.
        return 23040;
    } // 1 FNBT is worth the same as 10 PNPT.
     // Uniswap sorts tokens by their contract address. So currency0 is PNTB and currency1 is FNBT.
     // price = currency1 / currency0, SO FNBT / PNPT = 0.10 / 0.01 = 10, and tick = log1.0001(price) * 2^96 = 23040.

    function createPool(uint160 sqrtPriceX96) external onlyOwner returns (bytes32 poolId) {
        PoolKey memory key = _poolKey();
        poolManager.initialize(key, sqrtPriceX96);
        poolId = PoolId.unwrap(key.toId());
        createdPools[poolId] = true;
        emit PoolCreated(poolId, currency0, currency1, FEE_TIER, TICK_SPACING, HOOKS, sqrtPriceX96);
    }

    function mintLiquidity( 
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint256 positionId, bytes32 poolId) { 
        // 1) Validate inputs 
        if (amount0Desired == 0 && amount1Desired == 0) revert InvalidAmount();
        if (tickLower >= tickUpper) revert InvalidTickRange();
        if (tickLower % TICK_SPACING != 0 || tickUpper % TICK_SPACING != 0) revert InvalidTickRange();

        // 2) Ensure range covers the assignment target tick
        int24 target = getTargetTick();
        if (tickLower > target || tickUpper < target) revert TickRangeDoesNotCoverAssignmentPrice();

        // 3) Resolve and verify the pool
        PoolKey memory key = _poolKey();
        poolId = PoolId.unwrap(key.toId());
        if (!createdPools[poolId]) revert PoolNotCreated();

        // 4) Compute liquidity from desired amounts at current price
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtLower, sqrtUpper, amount0Desired, amount1Desired
        );

        // 5) Pull tokens from owner into this contract
        if (amount0Desired > 0) IERC20(currency0).transferFrom(msg.sender, address(this), amount0Desired);
        if (amount1Desired > 0) IERC20(currency1).transferFrom(msg.sender, address(this), amount1Desired);

        // 6) Approve Permit2 so PositionManager can settle
       address permit2 = address(Permit2Forwarder(address(positionManager)).permit2());
        IERC20(currency0).approve(permit2, type(uint256).max);
        IERC20(currency1).approve(permit2, type(uint256).max);

        // 7) Build actions and execute
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key, tickLower, tickUpper, liquidity, type(uint128).max, type(uint128).max, msg.sender, bytes("")
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        positionId = positionManager.nextTokenId(); // Get the next position ID before minting, so we can verify it after the mint action is executed.
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 60);

        // 8) Verify mint succeeded
        require(positionManager.getPositionLiquidity(positionId) == liquidity, "mint failed");

        // 9) Refund dust and emit
        uint256 bal0 = IERC20(currency0).balanceOf(address(this));
        uint256 bal1 = IERC20(currency1).balanceOf(address(this));
        if (bal0 > 0) IERC20(currency0).transfer(msg.sender, bal0);
        if (bal1 > 0) IERC20(currency1).transfer(msg.sender, bal1);

        emit LiquidityMinted(poolId, positionId, msg.sender, tickLower, tickUpper, liquidity); // Emit an event to log the minting of liquidity. 
    }
}
