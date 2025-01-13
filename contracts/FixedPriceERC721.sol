// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IFixedPriceERC721 } from "./interfaces/IFixedPriceERC721.sol";

contract FixedPriceERC721 is 
    Ownable,
    ReentrancyGuard, 
    IERC721Receiver,
    IFixedPriceERC721 
{
    enum LotState {
        Active,     // sold == false && closed == false
        Sold,       // sold == true
        Closed      // closed == true
    }

    struct Lot {
        IERC721 item;     
        bool sold;
        bool closed;
        uint256 price;
        uint256 tokenId;
        address creator;
        address buyer;
    }

    uint256 public totalLots;
    uint256 private _feeValue;
    mapping (uint256 id => Lot) private _lots;
    uint24 public fee;	// 10^4 -> (0.01% .. 100%)

    modifier lotExist(uint256 id) {
        require(totalLots > id, ERC721LotNotExist());
        _;
    }

    modifier onlyCreator(uint256 id) {
        require(_lots[id].creator == msg.sender, FixedPriceERC721OnlyCreatorAllowed());
        _;
    }

    constructor(uint24 _fee) Ownable(msg.sender) {
        fee = _fee;

        emit FeeUpdated(0, fee);
    }

    /*/////////////////////////////////////////////
    ///////// Read functions             /////////
    ///////////////////////////////////////////*/
    function getLotState(uint256 id) public view returns (LotState) {
        if (_lots[id].sold) {
            return LotState.Sold;
        } else if (_lots[id].closed) {
            return LotState.Closed;
        } else {
            return LotState.Active;
        }
    }

    function _encodeState(LotState state) private pure returns (bytes32) {
        return bytes32(1 << uint8(state));
    }

    function _supportsERC721Interface(address contractAddress) private view returns (bool) {
        uint256 codeLength;

        assembly {
            codeLength := extcodesize(contractAddress)
        }

        if (codeLength == 0) {
            return false;
        }

        try IERC165(contractAddress).supportsInterface(0x80ac58cd) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    function getLotInfo(uint256 id) external view lotExist(id) returns (
        address item,
        LotState state,
        uint256 price,
        uint256 tokenId,
        address creator,
        address buyer
    ) 
    {
        Lot memory lot = _lots[id];
        return (
            address(lot.item),
            getLotState(id),
            lot.price,
            lot.tokenId,
            lot.creator,
            lot.buyer
        );
    }

    /*/////////////////////////////////////////////
    ///////// Write functions             ////////
    ///////////////////////////////////////////*/
    function addLot(
        address _item,
        uint256 tokenId,
        uint256 price
    ) external {
        if (price == 0) {
            revert ERC721InvalidInputData();
        }

        if (!_supportsERC721Interface(_item)) {
            revert ERC721NoERC721InterfaceSupport();
        }

        address creator = msg.sender;
        IERC721 item = IERC721(_item);
        if (item.ownerOf(tokenId) != creator) {
            revert ERC721OwnershipError();
        }

        item.safeTransferFrom(creator, address(this), tokenId);

        _lots[totalLots] = Lot({
                item: item,
                sold: false,
                closed: false,
                price: price,
                tokenId: tokenId,
                creator: creator,
                buyer: creator
        });

        emit LotAdded(totalLots, _item, tokenId, price, creator);

        totalLots++;
    }

    function buyLot(
        uint256 id
    ) external payable nonReentrant {
        if (getLotState(id) != LotState.Active) {
            revert ERC721UnexpectedState(_encodeState(LotState.Active));
        }

        uint256 value = msg.value;
        if (value != _lots[id].price) {
            revert FixedPriceERC721InsufficientValue();
        }

        address buyer = msg.sender;

        Lot storage lot = _lots[id];
        lot.sold = true;
        lot.buyer = buyer;

        lot.item.safeTransferFrom(address(this), buyer, lot.tokenId);
        uint256 feeValue = value * fee / 10000;
        uint256 price = value - feeValue;
        _feeValue += feeValue;

        (bool success, ) = lot.creator.call{value: price}("");
        require(success, ERC721TransactionFailed());

        emit LotSold(id, buyer, price);
    }

    function closeLot(
        uint256 id
    ) external lotExist(id) onlyCreator(id) {
        if (getLotState(id) != LotState.Active) {
            revert ERC721UnexpectedState(_encodeState(LotState.Active));
        }

        Lot storage lot = _lots[id];
        lot.closed = true;

        lot.item.safeTransferFrom(address(this), lot.creator, lot.tokenId);

        emit LotClosed(id);
    }

    function updateFee(uint24 newFee) external onlyOwner {
        require(fee != newFee, ERC721FeeUpdateFailed());

        emit FeeUpdated(fee, newFee);

        fee = newFee;
    }

    function withdrawFee(address to) external nonReentrant onlyOwner {
        require(_feeValue > 0, ERC721ZeroFeeValue());

        emit FeeWithdrawed(to, _feeValue);

        (bool success, ) = to.call{value: _feeValue}("");
        _feeValue = 0;	// use no reentrant 

        require(success, ERC721TransactionFailed());
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        emit TokenReceived(operator, from, tokenId, data);

        return this.onERC721Received.selector;
    }
}