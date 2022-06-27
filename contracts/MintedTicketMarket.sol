// MintedTicket Market contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "./IBEP20.sol";

interface IMintedTicketNFT {
	function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
	function balanceOf(address account, uint256 id) external view returns (uint256);
    function creatorOf(uint256 id) external view returns (address);
	function royalties(uint256 _tokenId) external view returns (uint256);	
}

contract MintedTicketMarket is Ownable, ERC1155Holder {
    using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.AddressSet;

	uint256 constant public PERCENTS_DIVIDER = 100;

	uint256 public feeAdmin = 5;	
	address public adminAddress;
	
    /* Pairs to swap NFT _id => price */
	struct Pair {
		uint256 pair_id;
		address collection;
		uint256 token_id;
		address creator;
		address owner;
		uint256 price;
		address tokenAdr;
        uint256 creatorFee;
        uint256 balance;
		bool bValid;		
	}
	
	// token id => Pair mapping
    mapping(uint256 => Pair) public pairs;
	uint256 public currentPairId;
    
	uint256 public totalSwapped; /* Total swap count */

	/** Events */
    event ItemListed(Pair pair);
	event ItemDelisted(uint256 pairId);
    event Swapped(address buyer, Pair pair, uint256 amount);

	constructor (address _adminAddress) {		
		adminAddress = _adminAddress;					
	}
	
	function setFee(uint256 _feeAdmin, 
		address _adminAddress) external onlyOwner {		
        feeAdmin = _feeAdmin;
		adminAddress = _adminAddress;		
    }

    function list(address _collection, uint256 _token_id, uint256 _price, address _tokenAdr, uint256 _amount) public {
		require(_price > 0, "invalid price");
		require(_amount > 0, "invalid amount");
		IMintedTicketNFT nftCollection = IMintedTicketNFT(_collection);

		require(nftCollection.balanceOf(msg.sender, _token_id) >= _amount, "invalid amount : amount have to be smaller than NFT balance");

		nftCollection.safeTransferFrom(msg.sender, address(this), _token_id, _amount, "List");		

		currentPairId = currentPairId.add(1);

		pairs[currentPairId].pair_id = currentPairId;
		pairs[currentPairId].collection = _collection;
		pairs[currentPairId].token_id = _token_id;
		pairs[currentPairId].creator = getCreator(_collection, _token_id);
        pairs[currentPairId].creatorFee = getRoyalties(_collection, _token_id);
		pairs[currentPairId].owner = msg.sender;		
		pairs[currentPairId].price = _price;
		pairs[currentPairId].tokenAdr = _tokenAdr;	
		pairs[currentPairId].balance = _amount;
        pairs[currentPairId].bValid = true;	

        emit ItemListed(pairs[currentPairId]);
    }

    function delist(uint256 _pairId) external {        
        require(pairs[_pairId].bValid, "not exist");
		require(pairs[_pairId].owner == msg.sender || msg.sender == owner(), "only owner can delist");

		IMintedTicketNFT nftCollection = IMintedTicketNFT(pairs[_pairId].collection);
        nftCollection.safeTransferFrom(address(this), pairs[_pairId].owner, pairs[_pairId].token_id, pairs[_pairId].balance, "delist Marketplace");     
		pairs[_pairId].balance = 0;
        pairs[_pairId].bValid = false;
        emit ItemDelisted(_pairId);        
    }


    function buy(uint256 _id, uint256 _amount) external payable{
		require(pairs[_id].bValid, "invalid Pair id");
		require(pairs[_id].balance >= _amount, "insufficient NFT balance");
        require(pairs[_id].owner != msg.sender, "owner can not buy");

		Pair memory pair = pairs[_id];

		uint256 totalAmount = pair.price.mul(_amount);

		if (pairs[_id].tokenAdr == address(0x0)) {
            require(msg.value >= totalAmount, "too small amount");

			// transfer coin to adminAddress
			if(feeAdmin > 0) {
				payable(adminAddress).transfer(totalAmount.mul(feeAdmin).div(PERCENTS_DIVIDER));			
			}

			// transfer coin to creator
			if(pair.creatorFee > 0) {
				payable(pair.creator).transfer(totalAmount.mul(pair.creatorFee).div(PERCENTS_DIVIDER));			
			}

			// transfer coin to owner
			uint256 ownerPercent = PERCENTS_DIVIDER.sub(feeAdmin).sub(pair.creatorFee);
			payable(pair.owner).transfer(totalAmount.mul(ownerPercent).div(PERCENTS_DIVIDER));			
        } else {
			IBEP20 governanceToken = IBEP20(pair.tokenAdr);
			require(governanceToken.transferFrom(msg.sender, address(this), totalAmount), "insufficient token balance");

			// transfer governance token to adminAddress
			require(governanceToken.transfer(adminAddress, totalAmount.mul(feeAdmin).div(PERCENTS_DIVIDER)), "failed to transfer Admin fee");
			
			// transfer governance token to creator
			require(governanceToken.transfer(pair.creator, totalAmount.mul(pair.creatorFee).div(PERCENTS_DIVIDER)), "failed to transfer creator fee");
			
			// transfer governance token to owner
			uint256 ownerPercent = PERCENTS_DIVIDER.sub(feeAdmin).sub(pair.creatorFee);
			require(governanceToken.transfer(pair.owner, totalAmount.mul(ownerPercent).div(PERCENTS_DIVIDER)), "failed to transfer owner");		

		}

		// transfer NFT token to buyer
		IMintedTicketNFT nftCollection = IMintedTicketNFT(pairs[_id].collection);

		nftCollection.safeTransferFrom(address(this), msg.sender, pair.token_id, _amount, "buy from Marketplace");

		pairs[_id].balance = pairs[_id].balance.sub(_amount);
		if (pairs[_id].balance == 0) {
			pairs[_id].bValid = false;
		}	
		
		totalSwapped = totalSwapped.add(1);

        emit Swapped(msg.sender, pairs[_id], _amount);		
    }

	function getRoyalties(address collection, uint256 _tokenID) view private returns(uint256) {
        IMintedTicketNFT nft = IMintedTicketNFT(collection); 
        try nft.royalties(_tokenID) returns (uint256 value) {
            return value;
        } catch {
            return 0;
        }
    }

	function getCreator(address collection, uint256 _tokenID) view private returns(address) {
        IMintedTicketNFT nft = IMintedTicketNFT(collection); 
        try nft.creatorOf(_tokenID) returns (address creatorAddress) {
            return creatorAddress;
        } catch {
            return address(0x0);
        }
    }

}