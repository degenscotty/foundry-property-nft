// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PropertyNFT is ERC721, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error PropertyNFT__PropertyAlreadyExists();
    error PropertyNFT__NoFractionsAvailable();
    error PropertyNFT__InsufficientPayment();
    error PropertyNFT__NotEnoughFractionsAvailable();
    error PropertyNFT__InsufficientFractions();
    error PropertyNFT__ContractLacksFunds();
    error PropertyNFT__BuyPriceMustBeGreaterThanOrEqualToSellPrice();
    error PropertyNFT__PropertyDoesNotExist();
    error PropertyNFT__WithdrawFailed();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Counter for tokenIds
    uint256 public s_tokenIdCounter;

    // Mapping from tokenId to its total fractional supply
    mapping(uint256 => uint256) public s_fractionalSupply;

    // Mapping from tokenId to investor address to their fractional ownership
    mapping(uint256 => mapping(address => uint256)) public s_fractionalBalance;

    // Price per fractional unit to buy (in ether, adjustable by owner)
    uint256 public s_buyFractionPrice;

    // Price per fractional unit to sell back (in ether, adjustable by owner)
    uint256 public s_sellFractionPrice;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    // Event for fractional ownership transactions
    event FractionsBought(uint256 indexed tokenId, address buyer, uint256 amount, uint256 cost);
    event FractionsSold(uint256 indexed tokenId, address seller, uint256 amount, uint256 payout);
    event PropertyMinted(uint256 indexed tokenId, uint256 totalFractions);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        uint256 initialBuyPrice,
        uint256 initialSellPrice
    ) ERC721("PropertyNFT", "PNFT") Ownable(msg.sender) {
        s_buyFractionPrice = initialBuyPrice; // in ether
        s_sellFractionPrice = initialSellPrice; // in ether
        s_tokenIdCounter = 0; // Start counter at 0
    }

    // Mint a new property NFT with a specified fractional supply
    function mintProperty(uint256 totalFractions) external onlyOwner returns (uint256) {
        uint256 newTokenId = s_tokenIdCounter;
        s_tokenIdCounter += 1; // Increment counter

        if (s_fractionalSupply[newTokenId] != 0) {
            revert PropertyNFT__PropertyAlreadyExists();
        }
        _safeMint(msg.sender, newTokenId); // Mint to the contract itself
        s_fractionalSupply[newTokenId] = totalFractions;
        s_fractionalBalance[newTokenId][address(this)] = totalFractions; // Contract holds all fractions initially

        emit PropertyMinted(newTokenId, totalFractions);
        return newTokenId;
    }

    // Modifier to check if a property exists
    modifier exists(uint256 tokenId) {
        if (s_fractionalSupply[tokenId] == 0) {
            revert PropertyNFT__PropertyDoesNotExist();
        }
        _;
    }

    // Buy fractional ownership from the contract
    function buyFraction(uint256 tokenId, uint256 amount) external payable exists(tokenId) {
        if (msg.value < amount * s_buyFractionPrice) {
            revert PropertyNFT__InsufficientPayment();
        }
        if (s_fractionalBalance[tokenId][address(this)] < amount) {
            revert PropertyNFT__NotEnoughFractionsAvailable();
        }

        // Transfer fractions from contract to buyer
        s_fractionalBalance[tokenId][address(this)] -= amount;
        s_fractionalBalance[tokenId][msg.sender] += amount;

        // ETH stays in the contract
        emit FractionsBought(tokenId, msg.sender, amount, msg.value);
    }

    // Sell fractional ownership back to the contract
    function sellFraction(uint256 tokenId, uint256 amount) external exists(tokenId) {
        if (s_fractionalBalance[tokenId][msg.sender] < amount) {
            revert PropertyNFT__InsufficientFractions();
        }
        uint256 payout = amount * s_sellFractionPrice;
        if (address(this).balance < payout) {
            revert PropertyNFT__ContractLacksFunds();
        }

        // Transfer fractions from seller back to contract
        s_fractionalBalance[tokenId][msg.sender] -= amount;
        s_fractionalBalance[tokenId][address(this)] += amount;

        // Send ETH to the seller
        payable(msg.sender).transfer(payout);

        emit FractionsSold(tokenId, msg.sender, amount, payout);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEWER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // Get the current token ID counter (next available tokenId)
    function getNextTokenId() external view returns (uint256) {
        return s_tokenIdCounter;
    }

    // Get the total fractional supply for a specific property
    function getTotalFractions(uint256 tokenId) external view exists(tokenId) returns (uint256) {
        return s_fractionalSupply[tokenId];
    }

    // Get the fractional balance of an investor for a specific property
    function getFractionalBalance(
        uint256 tokenId,
        address investor
    ) external view exists(tokenId) returns (uint256) {
        return s_fractionalBalance[tokenId][investor];
    }

    // Get the number of fractions available for purchase from the contract
    function getAvailableFractions(
        uint256 tokenId
    ) external view exists(tokenId) returns (uint256) {
        return s_fractionalBalance[tokenId][address(this)];
    }

    // Get the total cost to buy a specified amount of fractions
    function getCostToBuyFractions(
        uint256 tokenId,
        uint256 amount
    ) external view exists(tokenId) returns (uint256) {
        return amount * s_buyFractionPrice;
    }

    // Get the total payout for selling a specified amount of fractions
    function getPayoutForSellingFractions(
        uint256 tokenId,
        uint256 amount
    ) external view exists(tokenId) returns (uint256) {
        return amount * s_sellFractionPrice;
    }

    // Get the owner of a specific property NFT (always the contract)
    function getPropertyOwner(uint256 tokenId) external view exists(tokenId) returns (address) {
        return ownerOf(tokenId);
    }

    // Get the current buy and sell prices
    function getBuyFractionPrice() external view returns (uint256) {
        return s_buyFractionPrice;
    }

    function getSellFractionPrice() external view returns (uint256) {
        return s_sellFractionPrice;
    }

    // Get the contract's ETH balance
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // Update buy and sell prices (only owner)
    function setPrices(uint256 newBuyPrice, uint256 newSellPrice) external onlyOwner {
        if (newBuyPrice < newSellPrice) {
            revert PropertyNFT__BuyPriceMustBeGreaterThanOrEqualToSellPrice();
        }
        s_buyFractionPrice = newBuyPrice;
        s_sellFractionPrice = newSellPrice;
    }

    // Withdraw ETH from the contract (only owner)
    function withdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        if (!success) revert PropertyNFT__WithdrawFailed(); // Ensure the transfer was successful
    }

    // Allow the contract to receive ETH (e.g., for funding payouts)
    receive() external payable {}
}
