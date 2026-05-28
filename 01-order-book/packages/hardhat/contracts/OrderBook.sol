// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract OrderBook { // Main contract for the order book, allowing users to place, match, and cancel orders
    using SafeERC20 for IERC20;
    enum OrderType { Buy, Sell }

    struct Order { // Struct to represent an order in the order book
        address trader;
        OrderType orderType;
        uint256 amount;
        uint256 remaining;
        uint256 price;
        uint256 escrow;
        bool open;
    }

    IERC20 public tokenA; // ERC20 token being traded (e.g., PNPToken)
    IERC20 public tokenB;
    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders; // Mapping of order ID to Order struct, storing all orders in the order book

    event OrderPlaced( 
        uint256 id, 
        address trader,
        OrderType orderType,
        address tokenGive,
        address tokenGet,
        uint256 amount,
        uint256 price
    );
    event OrderMatched(uint256 buyId, uint256 sellId, uint256 fillAmount, uint256 price); // Event emitted when two orders are matched
    event OrderCanceled(uint256 id, address trader, uint256 refund); // Event emitted when an order is canceled, includes refund amount

    error InvalidAmount();
    error InvalidPrice(); 
    error PriceMismatch();
    error UnauthorizedCancellation();

    constructor(address _tokenA, address _tokenB) { // Initialize the order book with two ERC20 token addresses
        tokenA = IERC20(_tokenA); // Initialize tokenA with the provided address
        tokenB = IERC20(_tokenB);
    }

    function isOpen(uint256 orderId) external view returns (bool) { // Check if the order with the given ID is still open
        return orders[orderId].open; // Return the open status of the order
    }

    function remaining(uint256 orderId) external view returns (uint256) { // Get the remaining amount of the order with the given ID
        return orders[orderId].remaining;// Return the remaining amount of the order
    }

    function placeBuyOrder(uint256 amount, uint256 price) external returns (uint256 orderId) { // Place a buy order for a specified amount and price, returns the order ID of the newly created order
        if (amount == 0) revert InvalidAmount();
        if (price == 0) revert InvalidPrice();

        uint256 quoteAmount = amount * price;
        tokenB.safeTransferFrom(msg.sender, address(this), quoteAmount); // Transfer the quote amount (amount * price) of tokenB from the buyer to the order book contract as escrow    

        orderId = nextOrderId++; // Assign the next available order ID to this new order and increment the counter for the next order
        orders[orderId] = Order({
            trader: msg.sender,
            orderType: OrderType.Buy,
            amount: amount,
            remaining: amount,
            price: price,
            escrow: quoteAmount,
            open: true
        });

        emit OrderPlaced(orderId, msg.sender, OrderType.Buy, address(tokenB), address(tokenA), amount, price); // Emit an event to log the placement of the new buy order, including details such as order ID, trader address, order type, tokens involved, amount, and price
    }

    function placeSellOrder(uint256 amount, uint256 price) external returns (uint256 orderId) { // Place a sell order for a specified amount and price, returns the order ID of the newly created order
        if (amount == 0) revert InvalidAmount();
        if (price == 0) revert InvalidPrice();

        tokenA.safeTransferFrom(msg.sender, address(this), amount); // Transfer the amount of tokenA from the seller to the order book contract as escrow

        orderId = nextOrderId++;
        orders[orderId] = Order({
            trader: msg.sender,
            orderType: OrderType.Sell,
            amount: amount,
            remaining: amount,
            price: price,
            escrow: amount,
            open: true
        });

        emit OrderPlaced(orderId, msg.sender, OrderType.Sell, address(tokenA), address(tokenB), amount, price);

    }

       function matchOrders(uint256 buyOrderId, uint256 sellOrderId) external { // Match a buy order and a sell order by their IDs, executing the trade if the price conditions are met
        Order storage buy = orders[buyOrderId]; // Retrieve the buy order from storage using the provided buy order ID
        Order storage sell = orders[sellOrderId]; // Retrieve the sell order from storage using the provided sell order ID

        if (buy.price < sell.price) revert PriceMismatch(); // Ensure that the buy order price is greater than or equal to the sell order price for a valid match

        uint256 fillAmount = buy.remaining < sell.remaining ? buy.remaining : sell.remaining; // Calculate the fill amount as the minimum of the remaining amounts of the buy and sell orders to determine how much can be traded in this match

        uint256 quotePaid = fillAmount * sell.price;

        buy.remaining -= fillAmount; // Update the remaining amount of the buy order by subtracting the fill amount
        sell.remaining -= fillAmount; // Update the remaining amount of the sell order by subtracting the fill amount
        buy.escrow -= quotePaid;
        sell.escrow -= fillAmount;

        tokenA.safeTransfer(buy.trader, fillAmount); // Transfer the filled amount of tokenA from the order book contract to the buyer's address
        tokenB.safeTransfer(sell.trader, quotePaid);

        if (buy.remaining == 0) buy.open = false;
        if (sell.remaining == 0) sell.open = false;

        emit OrderMatched(buyOrderId, sellOrderId, fillAmount, sell.price); // Emit an event to log the details of the matched orders, including the buy order ID, sell order ID, filled amount, and price at which the trade was executed
    }

    function cancelOrder(uint256 orderId) external { // Cancel an open order by its ID, allowing the trader to retrieve their escrowed funds if they are the owner of the order
        Order storage order = orders[orderId];

        if (order.trader != msg.sender) revert UnauthorizedCancellation(); // Ensure that only the trader who placed the order can cancel it to prevent unauthorized cancellations

        uint256 refund = order.escrow;
        order.escrow = 0;
        order.open = false;

        if (order.orderType == OrderType.Buy) { // If the order being canceled is a buy order, refund the escrowed tokenB to the trader
            tokenB.safeTransfer(order.trader, refund);
        } else {
            tokenA.safeTransfer(order.trader, refund); // If the order being canceled is a sell order, refund the escrowed tokenA to the trader
        }

        emit OrderCanceled(orderId, order.trader, refund); // Emit an event to log the cancellation of the order, including the order ID, trader address, and refund amount returned to the trader upon cancellation
    }
}


