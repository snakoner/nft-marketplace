// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IFixedPrice {
    error OnlyCreatorAllowed();

    error InsufficientValue();

    event LotAdded(
        uint256 indexed id,
        address indexed token,
        uint256 tokenId,
        uint256 price,
        address indexed creator
    );

    event LotSold (
        uint256 indexed id,
        address indexed buyer,
        uint256 price
    );

    event LotClosed (
        uint256 indexed id
    );
}