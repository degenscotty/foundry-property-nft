// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {PropertyNFT} from "../src/PropertyNFT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PropertyNFTTest is Test {
    PropertyNFT public propertyNFT;
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    uint256 public constant INITIAL_BUY_PRICE = 0.1 ether;
    uint256 public constant INITIAL_SELL_PRICE = 0.05 ether;
    uint256 public constant TOTAL_FRACTIONS = 100;

    event FractionsBought(uint256 indexed tokenId, address buyer, uint256 amount, uint256 cost);
    event FractionsSold(uint256 indexed tokenId, address seller, uint256 amount, uint256 payout);
    event PropertyMinted(uint256 indexed tokenId, uint256 totalFractions);

    function setUp() public {
        vm.prank(owner);
        propertyNFT = new PropertyNFT(INITIAL_BUY_PRICE, INITIAL_SELL_PRICE);
        vm.deal(user1, 100 ether); // Fund user1 with ETH
        vm.deal(user2, 100 ether); // Fund user2 with ETH
        vm.deal(address(propertyNFT), 5 ether); // Fund contract for payouts
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function test_ConstructorSetsInitialValues() view public {
        assertEq(propertyNFT.s_buyFractionPrice(), INITIAL_BUY_PRICE);
        assertEq(propertyNFT.s_sellFractionPrice(), INITIAL_SELL_PRICE);
        assertEq(propertyNFT.s_tokenIdCounter(), 0);
        assertEq(propertyNFT.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT PROPERTY TESTS
    //////////////////////////////////////////////////////////////*/
    function test_MintPropertyAsOwner() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit PropertyMinted(0, TOTAL_FRACTIONS);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);

        assertEq(tokenId, 0);
        assertEq(propertyNFT.s_fractionalSupply(0), TOTAL_FRACTIONS);
        assertEq(propertyNFT.s_fractionalBalance(0, address(propertyNFT)), TOTAL_FRACTIONS);
        assertEq(propertyNFT.ownerOf(tokenId), owner);
        assertEq(propertyNFT.balanceOf(owner), 1);
    }

    function test_MintPropertyNotOwnerReverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1)); // Pass user1 as the argument
        propertyNFT.mintProperty(TOTAL_FRACTIONS);
    }

    /*//////////////////////////////////////////////////////////////
                            BUY FRACTION TESTS
    //////////////////////////////////////////////////////////////*/
    function test_BuyFractionSuccess() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);

        uint256 amount = 10;
        uint256 cost = amount * INITIAL_BUY_PRICE;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit FractionsBought(tokenId, user1, amount, cost);
        propertyNFT.buyFraction{value: cost}(tokenId, amount);

        assertEq(propertyNFT.s_fractionalBalance(tokenId, user1), amount);
        assertEq(propertyNFT.s_fractionalBalance(tokenId, address(propertyNFT)), TOTAL_FRACTIONS - amount);
        assertEq(address(propertyNFT).balance, 5 ether + cost);
    }

    function test_BuyFractionInsufficientPaymentReverts() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.PropertyNFT__InsufficientPayment.selector));
        propertyNFT.buyFraction{value: 0.5 ether}(tokenId, 10); // Less than required
    }

    function test_BuyFractionNotEnoughFractionsReverts() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.PropertyNFT__NotEnoughFractionsAvailable.selector));
        propertyNFT.buyFraction{value: 10.1 ether}(tokenId, TOTAL_FRACTIONS + 1); // More than available
    }

    function test_BuyFractionNonExistentPropertyReverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.PropertyNFT__PropertyDoesNotExist.selector));
        propertyNFT.buyFraction{value: 1 ether}(999, 10);
    }

    /*//////////////////////////////////////////////////////////////
                            SELL FRACTION TESTS
    //////////////////////////////////////////////////////////////*/
    function test_SellFractionSuccess() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);

        uint256 amount = 10;
        uint256 cost = amount * INITIAL_BUY_PRICE;
        vm.prank(user1);
        propertyNFT.buyFraction{value: cost}(tokenId, amount);

        uint256 payout = amount * INITIAL_SELL_PRICE;
        uint256 user1BalanceBefore = user1.balance;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit FractionsSold(tokenId, user1, amount, payout);
        propertyNFT.sellFraction(tokenId, amount);

        assertEq(propertyNFT.s_fractionalBalance(tokenId, user1), 0);
        assertEq(propertyNFT.s_fractionalBalance(tokenId, address(propertyNFT)), TOTAL_FRACTIONS);
        assertEq(user1.balance, user1BalanceBefore + payout);
        assertEq(address(propertyNFT).balance, 5 ether + cost - payout);
    }

    function test_SellFractionInsufficientFractionsReverts() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.PropertyNFT__InsufficientFractions.selector));
        propertyNFT.sellFraction(tokenId, 10); // User1 has 0 fractions
    }

    function test_SellFractionContractLacksFundsReverts() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);

        uint256 amount = 10;
        vm.prank(user1);
        propertyNFT.buyFraction{value: amount * INITIAL_BUY_PRICE}(tokenId, amount);

        // Drain contract funds
        vm.prank(owner);
        propertyNFT.withdraw();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.PropertyNFT__ContractLacksFunds.selector));
        propertyNFT.sellFraction(tokenId, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    function test_GetNextTokenId() public {
        assertEq(propertyNFT.getNextTokenId(), 0);
        vm.prank(owner);
        propertyNFT.mintProperty(TOTAL_FRACTIONS);
        assertEq(propertyNFT.getNextTokenId(), 1);
    }

    function test_GetTotalFractions() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);
        assertEq(propertyNFT.getTotalFractions(tokenId), TOTAL_FRACTIONS);
    }

    function test_GetFractionalBalance() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);
        assertEq(propertyNFT.getFractionalBalance(tokenId, address(propertyNFT)), TOTAL_FRACTIONS);
    }

    function test_GetAvailableFractions() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);
        assertEq(propertyNFT.getAvailableFractions(tokenId), TOTAL_FRACTIONS);
    }

    function test_GetCostToBuyFractions() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);
        assertEq(propertyNFT.getCostToBuyFractions(tokenId, 10), 10 * INITIAL_BUY_PRICE);
    }

    function test_GetPayoutForSellingFractions() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);
        assertEq(propertyNFT.getPayoutForSellingFractions(tokenId, 10), 10 * INITIAL_SELL_PRICE);
    }

    function test_GetPropertyOwner() public {
        vm.prank(owner);
        uint256 tokenId = propertyNFT.mintProperty(TOTAL_FRACTIONS);

        assertEq(propertyNFT.getPropertyOwner(tokenId), owner);
    }

    function test_GetBuyFractionPrice() public view {
        assertEq(propertyNFT.getBuyFractionPrice(), INITIAL_BUY_PRICE);
    }

    function test_GetSellFractionPrice() public view {
        assertEq(propertyNFT.getSellFractionPrice(), INITIAL_SELL_PRICE);
    }

    function test_GetContractBalance() public view {
        assertEq(propertyNFT.getContractBalance(), 5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    function test_SetPricesSuccess() public {
        uint256 newBuyPrice = 0.2 ether;
        uint256 newSellPrice = 0.1 ether;

        vm.prank(owner);
        propertyNFT.setPrices(newBuyPrice, newSellPrice);

        assertEq(propertyNFT.s_buyFractionPrice(), newBuyPrice);
        assertEq(propertyNFT.s_sellFractionPrice(), newSellPrice);
    }

    function test_SetPricesInvalidPricesReverts() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(PropertyNFT.PropertyNFT__BuyPriceMustBeGreaterThanOrEqualToSellPrice.selector)
        );
        propertyNFT.setPrices(0.05 ether, 0.1 ether); // Buy < Sell
    }

    function test_SetPricesNotOwnerReverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        propertyNFT.setPrices(0.2 ether, 0.1 ether);
    }

    function test_WithdrawSuccess() public {
        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        propertyNFT.withdraw();
        
        assertEq(owner.balance, ownerBalanceBefore + 5 ether);
        assertEq(address(propertyNFT).balance, 0);
    }

    function test_WithdrawNotOwnerReverts() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        propertyNFT.withdraw();
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVE FUNCTION TEST
    //////////////////////////////////////////////////////////////*/
    function test_ReceiveEther() public {
        uint256 initialBalance = address(propertyNFT).balance;
        vm.prank(user1);
        (bool success, ) = address(propertyNFT).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(propertyNFT).balance, initialBalance + 1 ether);
    }
}