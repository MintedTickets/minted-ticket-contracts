// MintedTicket NFT token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MintedTicketNFT is ERC1155, AccessControl {
    using SafeMath for uint256;

    uint256 constant public PERCENTS_DIVIDER = 100;
	uint256 constant public FEE_MAX_PERCENT = 20; // 20 %
    uint256 constant public FEE_MIN_PERCENT = 1; // 1 %

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bool private initialisable;
    string public collection_name;
    string public collection_uri;
    bool public isPublic;
    address public factory;
    address public owner;

    struct Item {
        uint256 id;
        address creator;
        string uri;
        uint256 royalty;
        uint256 supply;
    }
    uint256 public currentID;    
    mapping (uint256 => Item) public Items;


    event CollectionUriUpdated(string collection_uri);    
    event CollectionNameUpdated(string collection_name);
    event CollectionPublicUpdated(bool isPublic);
    event TokenUriUpdated(uint256 id, string uri);

    event ItemCreated(uint256 id, address creator, string uri, uint256 royalty, uint256 supply);

    constructor () ERC1155("MintedTicketNFT") {
        factory = msg.sender;
        initialisable = true;	
    }

    function initialize(string memory _name, string memory _uri, address creator, bool bPublic ) external {
        require(msg.sender == factory, "Only for factory");
        require(initialisable, "initialize() can be called only one time.");
		initialisable = false;
        
        _setURI(_uri);
        collection_name = _name;
        collection_uri = _uri;

        owner = creator;
        isPublic = bPublic;

        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(MINTER_ROLE, owner);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, AccessControl) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }


    /**
		Change & Get Collection Information
	 */
    function setCollectionURI(string memory newURI) public onlyOwner {
        collection_uri = newURI;
        _setURI(newURI);
        emit CollectionUriUpdated(newURI);
    }

    function setName(string memory newname) public onlyOwner {
        collection_name = newname;
        emit CollectionNameUpdated(newname);
    }

    function setPublic(bool bPublic) public onlyOwner {
        isPublic = bPublic;
        emit CollectionPublicUpdated(isPublic);
    }
    function getCollectionURI() external view returns (string memory) {
        return collection_uri;
    }
    function getCollectionName() external view returns (string memory) {
        return collection_name;
    }


    /**
		Change & Get Item Information
	 */
    function addItem(string memory _tokenURI, uint256 royalty, uint256 supply) public returns (uint256){
        require(royalty <= FEE_MAX_PERCENT, "too big royalties");
        require(royalty >= FEE_MIN_PERCENT, "too small royalties");
        require( hasRole(MINTER_ROLE, msg.sender) || isPublic,
            "Only minter can add item"
        );
        require(supply > 0, "supply can not be 0");

        currentID = currentID.add(1);    
        if (supply > 0) {
            _mint(msg.sender, currentID, supply, "Mint");
        }   
        
        Items[currentID] = Item(currentID, msg.sender, _tokenURI, royalty, supply);
        emit ItemCreated(currentID, msg.sender, _tokenURI, royalty, supply);
        return currentID;
    }

    function setTokenURI(uint256 _tokenId, string memory _newURI)
        public
        creatorOnly(_tokenId)
    {
        Items[_tokenId].uri = _newURI;
        emit TokenUriUpdated( _tokenId, _newURI);
    }

    function uri(uint256 _id) public view override returns (string memory) {
        require(_exists(_id), "ERC1155Tradable#uri: NONEXISTENT_TOKEN");
        // We have to convert string to bytes to check for existence

        bytes memory customUriBytes = bytes(Items[_id].uri);
        if (customUriBytes.length > 0) {
            return Items[_id].uri;
        } else {
            return super.uri(_id);
        }
    } 

    function totalSupply(uint256 _id) public view returns (uint256) {
        require(_exists(_id), "ERC1155Tradable#uri: NONEXISTENT_TOKEN");
        return Items[_id].supply;        
    }   

    function creatorOf(uint256 _tokenId) public view returns (address) {
        return Items[_tokenId].creator;
    }

    function royalties(uint256 _tokenId) public view returns (uint256) {
        return Items[_tokenId].royalty;
	}




    modifier onlyOwner() {
        require(owner == _msgSender(), "caller is not the owner");
        _;
    }

    function _exists(uint256 _id) internal view returns (bool) {
        return _id <= currentID;
    }

    /**
     * @dev Require _msgSender() to be the creator of the token id
     */
    modifier creatorOnly(uint256 _id) {
        require(
            Items[_id].creator == _msgSender(),
            "ERC721Tradable#creatorOnly: ONLY_CREATOR_ALLOWED"
        );
        _;
    }
}
