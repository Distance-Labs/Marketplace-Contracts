// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IKRC20 is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

contract NFTMarketplace is Context, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using Address for address;
    using SafeERC20 for IKRC20;

    address private immutable USDT; // Native ERC20 token for trades
    uint8 public tradeFee; // marketplace fee
    address private admin; // marketplace controller
    uint8 public constant minFees = 0; // 1% == 100 etc.
    uint16 public constant maxFees = 1000; // 1000 == 10%

    enum Status {
        Verified,
        Unverified
    } // status for verifying collections

    event ItemListed(
        address indexed seller,
        uint32 indexed tokenId,
        uint256 indexed price
    );
    event ItemUpdated(
        address indexed owner,
        uint32 indexed tokenId,
        uint256 indexed newPrice
    );
    event ItemSold(
        address indexed seller,
        address indexed buyer,
        uint32 indexed tokenId,
        uint256 price
    );
    event ItemDelisted(uint32 tokenId);
    event CollectionAdded(address collection);
    event CollectionUpdated(address collection);
    event CollectionUnverify(address collection);
    event CollectionRemoved(address collection);
    event OfferCreated(
        address indexed creator,
        address indexed owner,
        uint256 indexed value
    );
    event OfferUpdated(
        address indexed creator,
        address indexed owner,
        uint256 indexed value
    );
    event OfferCancelled(address creator, address collection, uint256 token);
    event OfferAccepted(
        address owner,
        address creator,
        address collection,
        uint256 token
    );
    event Pause(string reason);
    event Unpause(string reason);
    event TokenRecovery(address tokenAddress, uint256 amount);
    event NFTRecovery(address collectionAddress, uint256 tokenId);
    event PlatformUpdated(uint256 fees, address indexed admin);
    error PriceMustBeAboveZero(uint256 price);
    error NFTAlreadyListed(uint32 tokenId);

    constructor(
        uint8 _tradeFee, // trade fee to be in counts of 100: 1% == 100, 10% = 1000
        address _admin,
        address _USDT
    ) {
        tradeFee = _tradeFee;
        admin = _admin;
        USDT = _USDT;
        Ownable(_msgSender());
    }

    struct Listing {
        address seller;
        uint256 price;
    }
    struct Offer {
        address buyer;
        uint256 price;
    }
    struct Collection {
        address collectionAddress;
        uint256 royaltyFees;
        Status status;
    }

    mapping(address => mapping(uint256 => Listing)) public sellNFT;
    mapping(address => EnumerableSet.UintSet) private tokenIdExists;
    mapping(address => uint256) private revenue;
    mapping(address => mapping(address => EnumerableSet.UintSet))
        private offerExists;
    mapping(address => Collection) public collection;
    mapping(address => mapping(uint256 => mapping(address => Offer)))
        private offer;
    mapping(address => mapping(uint256 => EnumerableSet.AddressSet))
        private offerCreator;

    function userOffers(address _collection)
        external
        view
        returns (uint256[] memory tokens)
    {
        uint256 length = offerExists[_collection][_msgSender()].length();
        tokens = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = offerExists[_collection][_msgSender()].at(i);
        }
        return tokens;
    }

    function allCreators(address _collection, uint256 _tokenId)
        external
        view
        returns (address[] memory creators)
    {
        uint256 length = offerCreator[_collection][_tokenId].length();
        creators = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            creators[i] = offerCreator[_collection][_tokenId].at(i);
        }
        return creators;
    }

    function availableListings(address _collection)
        external
        view
        returns (uint256[] memory nfts, Listing[] memory nftInfo)
    {
        uint256 length = tokenIdExists[_collection].length();
        nfts = new uint256[](length);
        nftInfo = new Listing[](length);
        for (uint256 i = 0; i < length; i++) {
            nfts[i] = tokenIdExists[_collection].at(i);
            nftInfo[i] = sellNFT[_collection][nfts[i]];
        }
        return (nfts, nftInfo);
    }

    function availableOffers(address _collection, uint256 _tokenId)
        external
        view
        returns (address[] memory offerCount, Offer[] memory offerInfo)
    {
        uint256 length = offerCreator[_collection][_tokenId].length();
        offerCount = new address[](length);
        offerInfo = new Offer[](length);
        for (uint256 i = 0; i < length; i++) {
            offerCount[i] = offerCreator[_collection][_tokenId].at(i);
            offerInfo[i] = offer[_collection][_tokenId][offerCount[i]];
        }
        return (offerCount, offerInfo);
    }

    function supportedCollections()
        external
        view
        returns (address[] memory availableCollections)
    {
        uint256 length = collectionAddresses.length();
        availableCollections = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            availableCollections[i] = collectionAddresses.at(i);
        }
        return availableCollections;
    }

    modifier isAdmin() {
        require(_msgSender() == admin, "Caller != Marketplace Admin");
        _;
    }
    modifier isListed(address _collection, uint256 _tokenId) {
        require(
            tokenIdExists[_collection].contains(_tokenId),
            "NFT isn't listed for sale"
        );
        _;
    }
    modifier offerAvailable(
        address _collection,
        address _creator,
        uint256 _tokenId
    ) {
        require(
            offerExists[_collection][_creator].contains(_tokenId),
            "Offer doesn't exist"
        );
        _;
    }

    EnumerableSet.AddressSet private collectionAddresses;

    function list(
        address _collection,
        uint256 _tokenId,
        uint256 _price
    ) external whenNotPaused {
        IERC721 nft = IERC721(_collection);
        require(_msgSender() == nft.ownerOf(_tokenId), "msg.sender != owner");
        require(
            collectionAddresses.contains(_collection),
            "Collection is not listed"
        );
        require(
            nft.getApproved(_tokenId) == address(this),
            "Approve MacKett first"
        );
        if (tokenIdExists[_collection].contains(_tokenId)) {
            revert NFTAlreadyListed(uint32(_tokenId));
        }
        if (_price <= 0) {
            revert PriceMustBeAboveZero(_price);
        }
        sellNFT[_collection][_tokenId] = Listing(_msgSender(), _price);
        tokenIdExists[_collection].add(_tokenId);
        emit ItemListed(_msgSender(), uint32(_tokenId), _price);
    }

    function updateListing(
        address _collection,
        uint256 _tokenId,
        uint256 _newPrice
    ) external isListed(_collection, _tokenId) whenNotPaused returns (bool) {
        IERC721 nft = IERC721(_collection);
        require(_msgSender() == nft.ownerOf(_tokenId), "msg.sender != owner");
        require(
            nft.getApproved(_tokenId) == address(this),
            "MacKett isn't approved"
        );
        sellNFT[_collection][_tokenId].price = _newPrice;
        emit ItemUpdated(_msgSender(), uint32(_tokenId), _newPrice);
        return true;
    }

    function cancelListing(address _collection, uint256 _tokenId)
        external
        isListed(_collection, _tokenId)
        nonReentrant
    {
        IERC721 nft = IERC721(_collection);
        require(_msgSender() == nft.ownerOf(_tokenId), "msg.sender != owner");
        delete (sellNFT[_collection][_tokenId]);
        tokenIdExists[_collection].remove(_tokenId);
        emit ItemDelisted(uint32(_tokenId));
    }

    function buyNFT(
        address _collection,
        uint256 _tokenId,
        uint256 _price
    ) external isListed(_collection, _tokenId) whenNotPaused nonReentrant {
        IERC721 nft = IERC721(_collection);
        require(
            nft.getApproved(_tokenId) == address(this),
            "MacKett isn't approved to sell this NFT"
        );
        require(
            _price == sellNFT[_collection][_tokenId].price,
            "Price mismatch"
        );
        require(IKRC20(USDT).allowance(_msgSender(), address(this)) >= _price);
        IKRC20(USDT).safeTransferFrom(
            address(msg.sender),
            address(this),
            _price
        );
        _buyNFT(_collection, _tokenId, _price);
    }

    function _buyNFT(
        address _collection,
        uint256 _tokenId,
        uint256 _price
    ) private {
        Listing memory listing = sellNFT[_collection][_tokenId];
        IERC721 nft = IERC721(_collection);
        (uint256 amount, uint256 marketplaceFee, uint256 collectionFee) = _fees(
            _collection,
            _price
        );
        delete (sellNFT[_collection][_tokenId]);
        tokenIdExists[_collection].remove(_tokenId);
        if (offerCreator[_collection][_tokenId].contains(_msgSender())) {
            delete (offer[_collection][_tokenId][_msgSender()]);
            offerCreator[_collection][_tokenId].remove(_msgSender());
            offerExists[_collection][_msgSender()].remove(_tokenId);
        }
        if (collectionFee != 0) {
            revenue[collection[_collection].collectionAddress] += collectionFee;
        }
        if (marketplaceFee != 0) {
            revenue[admin] += marketplaceFee;
        }
        IKRC20(USDT).safeTransfer(listing.seller, amount);
        nft.safeTransferFrom(listing.seller, _msgSender(), _tokenId);
        emit ItemSold(listing.seller, _msgSender(), uint32(_tokenId), _price);
    }

    function _fees(address _collection, uint256 _price)
        internal
        view
        returns (
            uint256 amount,
            uint256 marketplaceFee,
            uint256 collectionFee
        )
    {
        marketplaceFee = (_price * tradeFee) / 10000;
        collectionFee = (_price * collection[_collection].royaltyFees) / 10000;
        amount = _price - (marketplaceFee + collectionFee);
        return (amount, marketplaceFee, collectionFee);
    }

    function addCollection(
        address _collection,
        address _collectionAddress,
        uint256 _royaltyFees
    ) external whenNotPaused isAdmin {
        require(
            !collectionAddresses.contains(_collection),
            "Collection exists"
        );
        require(
            IERC721(_collection).supportsInterface(0x80ac58cd),
            "NFT Standards, not supported"
        );
        require(
            _royaltyFees >= minFees && _royaltyFees <= (maxFees - tradeFee),
            "Royalty fees are high"
        );
        collectionAddresses.add(_collection);
        collection[_collection] = Collection(
            _collectionAddress,
            _royaltyFees,
            Status.Unverified
        );
        emit CollectionAdded(_collection);
    }

    function updateCollection(
        address _collection,
        address _collectionAddress,
        uint256 _royaltyFees
    ) external whenNotPaused isAdmin {
        require(collectionAddresses.contains(_collection), "N/A, can't verify");
        require(
            _royaltyFees >= minFees && _royaltyFees <= (maxFees - tradeFee),
            "Royalty fees issues"
        );
        collection[_collection] = Collection(
            _collectionAddress,
            _royaltyFees,
            Status.Verified
        );
        emit CollectionUpdated(_collection);
    }

    function unverifyCollection(address _collection) external isAdmin {
        require(collectionAddresses.contains(_collection), "N/A, can't verify");
        Collection storage collectionStatus = collection[_collection];
        collectionStatus.status = Status.Unverified;
        emit CollectionUnverify(_collection);
    }

    function createOffer(
        address _collection,
        uint256 _tokenId,
        uint256 _value
    )
        external
        isListed(_collection, _tokenId)
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(
            !offerExists[_collection][_msgSender()].contains(_tokenId),
            "Offer exists"
        );
        require(
            !offerCreator[_collection][_tokenId].contains(_msgSender()),
            "Two offer Instances"
        );
        require(
            IKRC20(USDT).allowance(_msgSender(), address(this)) >= _value,
            "Approve value first"
        );
        require(
            sellNFT[_collection][_tokenId].price != _value,
            "Value can't be the same"
        );
        IERC721 nft = IERC721(_collection);
        address itemOwner = nft.ownerOf(_tokenId);
        require(itemOwner != _msgSender(), "Owner can't make Offers");
        offer[_collection][_tokenId][_msgSender()] = Offer(
            _msgSender(),
            _value
        );
        offerExists[_collection][_msgSender()].add(_tokenId);
        offerCreator[_collection][_tokenId].add(_msgSender());
        emit OfferCreated(_msgSender(), itemOwner, _value);
        return true;
    }

    function updateOffer(
        address _collection,
        uint256 _tokenId,
        uint256 _newValue
    )
        external
        isListed(_collection, _tokenId)
        whenNotPaused
        nonReentrant
        offerAvailable(_collection, _msgSender(), _tokenId)
        returns (bool)
    {
        require(
            IKRC20(USDT).allowance(_msgSender(), address(this)) >= _newValue
        );
        require(
            sellNFT[_collection][_tokenId].price != _newValue,
            "Value can't be the same"
        );
        Offer storage changeOffer = offer[_collection][_tokenId][_msgSender()];
        require(changeOffer.price != _newValue, "New value must be provided");
        IERC721 nft = IERC721(_collection);
        address itemOwner = nft.ownerOf(_tokenId);
        changeOffer.price = _newValue;
        emit OfferUpdated(_msgSender(), itemOwner, _newValue);
        return true;
    }

    function cancelOffer(address _collection, uint256 _tokenId)
        external
        nonReentrant
        offerAvailable(_collection, _msgSender(), _tokenId)
    {
        delete (offer[_collection][_tokenId][_msgSender()]);
        offerExists[_collection][_msgSender()].remove(_tokenId);
        offerCreator[_collection][_tokenId].remove(_msgSender());
        emit OfferCancelled(_msgSender(), _collection, _tokenId);
    }

    function acceptOffer(
        address _collection,
        uint256 _tokenId,
        address _offerer
    ) external whenNotPaused nonReentrant {
        IERC721 nft = IERC721(_collection);
        require(
            nft.ownerOf(_tokenId) == _msgSender(),
            "NFT Owner !== msg.sender"
        );
        uint256 value = offer[_collection][_tokenId][_offerer].price;
        require(
            IKRC20(USDT).balanceOf(_offerer) >= value,
            "Offer creator balance is less than value"
        );
        require(
            IKRC20(USDT).allowance(_offerer, address(this)) >= value,
            "Offer creator allowance is less than value"
        );
        IKRC20(USDT).safeTransferFrom(_offerer, address(this), value);
        delete (offer[_collection][_tokenId][_offerer]);
        offerCreator[_collection][_tokenId].remove(_offerer);
        offerExists[_collection][_offerer].remove(_tokenId);
        delete (sellNFT[_collection][_tokenId]);
        tokenIdExists[_collection].remove(_tokenId);
        _acceptOffer(_collection, _tokenId, value, _offerer);
    }

    function _acceptOffer(
        address _collection,
        uint256 _tokenId,
        uint256 _price,
        address _offerInitiator
    ) private {
        IERC721 nft = IERC721(_collection);
        (uint256 amount, uint256 marketplaceFee, uint256 collectionFee) = _fees(
            _collection,
            _price
        );
        if (collectionFee != 0) {
            revenue[collection[_collection].collectionAddress] += collectionFee;
        }
        if (tradeFee != 0) {
            revenue[admin] += marketplaceFee;
        }
        IKRC20(USDT).safeTransfer(_msgSender(), amount);
        nft.safeTransferFrom(_msgSender(), _offerInitiator, _tokenId);
        emit OfferAccepted(
            _msgSender(),
            _offerInitiator,
            _collection,
            _tokenId
        );
    }

    function withdrawRevenue() external whenNotPaused nonReentrant {
        uint256 revenueGenerated = revenue[_msgSender()];
        require(revenueGenerated != 0, "N/A");
        revenue[_msgSender()] = 0;
        IKRC20(USDT).safeTransfer(_msgSender(), revenueGenerated);
    }

    //OnlyOwner function calls

    function recoverToken(address _token, uint256 _amount)
        external
        whenPaused
        onlyOwner
    {
        IKRC20(_token).safeTransfer(address(msg.sender), _amount);
        emit TokenRecovery(_token, _amount);
    }

    function recoverNFT(address _collection, uint256 _tokenId)
        external
        whenPaused
        onlyOwner
    {
        IERC721 nft = IERC721(_collection);
        nft.safeTransferFrom(address(this), address(msg.sender), _tokenId);
        emit NFTRecovery(_collection, _tokenId);
    }

    function updatePlatform(uint8 _newTradeFees, address _newAdmin)
        external
        whenPaused
        onlyOwner
    {
        tradeFee = _newTradeFees;
        admin = _newAdmin;
        emit PlatformUpdated(_newTradeFees, _newAdmin);
    }

    function pauseMarketplace(string calldata _reason)
        external
        whenNotPaused
        onlyOwner
    {
        _pause();
        emit Pause(_reason);
    }

    function unpauseMarketplace(string calldata _reason)
        external
        whenPaused
        onlyOwner
    {
        _unpause();
        emit Unpause(_reason);
    }
}
