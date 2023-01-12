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
    // Libraries
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using Address for address;
    using SafeERC20 for IKRC20;

    // Variables
    address private immutable USDT; // Native ERC20 token for trades
    uint8 private tradeFee; // marketplace fee
    address private admin; // marketplace controller
    uint8 private constant minFees = 0; // 1% == 100 etc.
    uint16 private constant maxFees = 1000; // 1000 == 10%
    address private proxyAdmin; // marketplace data management

    // Enums
    enum Status {
        Unverified,
        Verified
    }

    // Events
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
    event CollectionVerify(address collection);
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
        address indexed owner,
        address indexed creator,
        address collection,
        uint256 token
    );
    event TokenRecovery(address indexed tokenAddress, uint256 indexed amount);
    event NFTRecovery(
        address indexed collectionAddress,
        uint256 indexed tokenId
    );
    event TradeFeeUpdated(uint256 fees);
    event AdminUpdated(address indexed admin);
    event RevenueWithdrawn(address indexed eoa, uint256 indexed amount);
    event Pause(string reason);
    event Unpause(string reason);

    // Constructor
    /**
     * @notice Constructor for the marketplace
     * @param _tradeFee trade fee to be in counts of 100: 1% == 100, 10% = 1000
     * @param _admin address of the admin
     * @param _USDT address of the USDT token
     */
    constructor(
        uint8 _tradeFee, // trade fee to be in counts of 100: 1% == 100, 10% = 1000
        address _admin,
        address _USDT
    ) {
        tradeFee = _tradeFee;
        admin = _admin;
        proxyAdmin = _admin;
        USDT = _USDT;
        Ownable(_msgSender());
    }

    // Structs
    // Stores Listing data
    struct Listing {
        address seller;
        uint256 price;
        address collection;
        uint256 tokenId;
    }
    // Stores data about an Offer. The buyer and the offer value
    struct Offer {
        address buyer;
        uint256 price;
    }
    // A struct that tracks the royalty fees collection address, its royalty fees and state of its verification. Paramount for future updates when making the marketplace decentralized
    struct Collection {
        address collectionAddress;
        uint256 royaltyFees;
        Status status;
    }
    // An array of recent NFT listings
    Listing[] private recentlyListed;
    // An address set of all supported collections
    EnumerableSet.AddressSet private collectionAddresses;

    // data mappings
    // mapping from collection address to tokenId to the Listing struct, containing seller address and price
    mapping(address => mapping(uint256 => Listing)) private sellNFT;
    // mapping from collection address to an enumerable set of tokenIds. Used to keep track of token existence in the smart contract storage as listed
    mapping(address => EnumerableSet.UintSet) private tokenIdExists;
    // tracks the revenue generation for the protocol and the collection royalty fees
    mapping(address => uint256) private revenue;
    // mapping from an EOA address to a collection address then to an enumerable set of tokenIds. Used to keep track of token existence in the smart contract storage as having an offer created by a user for that NFT collection, tokenId
    mapping(address => mapping(address => EnumerableSet.UintSet))
        private userOfferExists;
    // Maps a collection address to its information
    mapping(address => Collection) private collection;
    // mapping from a collection to a tokenId to an offer creator which maps to the details of the Offer created
    mapping(address => mapping(uint256 => mapping(address => Offer)))
        private offer;
    // mapping from a collection to a tokenId that stores all addresses that has created an offer for that NFT. Used to track and limit users from creating multiple offer instances and allow offer updates only if the offer was created before
    mapping(address => mapping(uint256 => EnumerableSet.AddressSet))
        private offerCreator;
    // mapping from a collection address to an array of recent listings for that collection
    mapping(address => Listing[]) private collectionRecentlyListed;

    /// All read functions
    /**
     * @notice Generate all recent listings
     */
    function getAllRecentListings()
        external
        view
        returns (Listing[] memory recentNFTListings)
    {
        uint256 length = recentlyListed.length;
        recentNFTListings = new Listing[](length);
        for (uint256 i = 0; i < length; i++) {
            recentNFTListings[i] = recentlyListed[i];
        }
        return recentNFTListings;
    }

    /**
     * @notice Generate all recent listings for a collection
     * @param _collection address to check listings from
     */
    function getCollectionRecentListings(address _collection)
        external
        view
        returns (Listing[] memory dataPoints)
    {
        uint256 length = collectionRecentlyListed[_collection].length;
        dataPoints = new Listing[](length);
        for (uint256 i = 0; i < length; i++) {
            dataPoints[i] = collectionRecentlyListed[_collection][i];
        }
        return dataPoints;
    }

    /**
     * @notice Generate all offers a user has created for a set of NFTs in a collection
     * @param _collection address to check offers from
     */
    function getUserOffers(address _collection)
        external
        view
        returns (uint256[] memory tokens)
    {
        uint256 length = userOfferExists[_collection][_msgSender()].length();
        tokens = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = userOfferExists[_collection][_msgSender()].at(i);
        }
        return tokens;
    }

    /**
     * @notice Generate listing info for a collection
     * @param _collection address to check listings from
     */
    function getAllListings(address _collection)
        external
        view
        returns (Listing[] memory listingData)
    {
        uint256 length = tokenIdExists[_collection].length();
        uint256[] memory nfts = new uint256[](length);
        listingData = new Listing[](length);
        for (uint256 i = 0; i < length; i++) {
            nfts[i] = tokenIdExists[_collection].at(i);
            listingData[i] = sellNFT[_collection][nfts[i]];
        }
        return listingData;
    }

    /** 
        @notice a getter function that returns all the offers for all NFTs in a collection, gets all listed tokenIds from tokenIdExists, gets the length of offerCreators for each, reads from the offer mapping and returns a struct of Offers
        @param _collection address to check offers from
    */
    function getAllOffers(address _collection)
        external
        view
        returns (Offer[][] memory offerInfo)
    {
        uint256 length = tokenIdExists[_collection].length();
        uint256[] memory nfts = new uint256[](length);
        offerInfo = new Offer[][](length);
        for (uint256 i = 0; i < length; i++) {
            nfts[i] = tokenIdExists[_collection].at(i);
            uint256 offerLength = offerCreator[_collection][nfts[i]].length();
            offerInfo[i] = new Offer[](offerLength);
            for (uint256 j = 0; j < offerLength; j++) {
                offerInfo[i][j] = offer[_collection][nfts[i]][
                    offerCreator[_collection][nfts[i]].at(j)
                ];
            }
        }
        return offerInfo;
    }

    /**
     * @notice Get all collections supported by the marketplace
     */
    function getSupportedCollections()
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

    /**
     * @notice Get all listings and offers for a set of NFTs in a collection. Function also calls availableOffers() to get all offers for each NFT in the collection
     * @param _collection address to check offers from
     */
    function getAllListingsAndOffers(address _collection)
        public
        view
        returns (Listing[] memory listingData, Offer[][] memory offerInfo)
    {
        uint256 length = tokenIdExists[_collection].length();
        uint256[] memory nfts = new uint256[](length);
        listingData = new Listing[](length);
        offerInfo = new Offer[][](length);
        for (uint256 i = 0; i < length; i++) {
            nfts[i] = tokenIdExists[_collection].at(i);
            listingData[i] = sellNFT[_collection][nfts[i]];
            uint256 offerLength = offerCreator[_collection][nfts[i]].length();
            address[] memory offerCreators = new address[](offerLength);
            offerInfo[i] = new Offer[](offerLength);
            for (uint256 j = 0; j < offerLength; j++) {
                offerCreators[j] = offerCreator[_collection][nfts[i]].at(j);
                offerInfo[i][j] = offer[_collection][nfts[i]][offerCreators[j]];
            }
        }
        return (listingData, offerInfo);
    }

    /**
     * @notice a public getter function to read from sellNFT mapping to get listing data for an  NFT of a collection
     * @param _collection address to check listing from
     * @param _tokenId uint256 to check listing from
     */
    function getListing(address _collection, uint256 _tokenId)
        public
        view
        returns (Listing memory)
    {
        return sellNFT[_collection][_tokenId];
    }

    /**
     * @notice Generate all offers available for a tokenId in a collection
     * @param _collection address to check offers from
     * @param _tokenId uint256 to check offers from
     */
    function getOffers(address _collection, uint256 _tokenId)
        public
        view
        returns (Offer[] memory offerInfo)
    {
        uint256 length = offerCreator[_collection][_tokenId].length();
        address[] memory offerCreators = new address[](length);
        offerInfo = new Offer[](length);
        for (uint256 i = 0; i < length; i++) {
            offerCreators[i] = offerCreator[_collection][_tokenId].at(i);
            offerInfo[i] = offer[_collection][_tokenId][offerCreators[i]];
        }
        return offerInfo;
    }

    /**
     * @notice a public getter function to get a collection information from the collection mapping
     * @param _collection address to check offer from
     */
    function getCollectionData(address _collection)
        public
        view
        returns (Collection memory)
    {
        return collection[_collection];
    }

    // Modifiers
    // modifier to check that the NFT is approved for sale
    modifier isApproved(address _collection, uint256 _tokenId) {
        require(
            IERC721(_collection).getApproved(_tokenId) == address(this),
            "Marketplace not approved to sell NFT"
        );
        _;
    }
    // modifier to check that only admin can call the function
    modifier isAdmin() {
        require(_msgSender() == admin, "Caller != Marketplace Admin");
        _;
    }
    // modifier to check that only proxy admin can call the function
    modifier isProxyAdmin() {
        require(
            _msgSender() == proxyAdmin,
            "Caller != Marketplace Proxy Admin"
        );
        _;
    }
    // modifier to check that price is > 0
    modifier isPriceValid(uint256 _price) {
        require(_price > 0, "Price must be > 0");
        _;
    }
    // modifier to check if a collection is supported
    modifier isCollection(address _collection) {
        require(
            collectionAddresses.contains(_collection),
            "Collection not supported"
        );
        _;
    }
    // modifier to check if msg.sender is the NFT owner
    modifier isNftOwner(address _collection, uint256 _tokenId) {
        require(
            IERC721(_collection).ownerOf(_tokenId) == _msgSender(),
            "Caller != NFT Owner"
        );
        _;
    }
    // modifier to check if msg.sender is the NFT seller
    modifier isSeller(address _collection, uint256 _tokenId) {
        require(
            sellNFT[_collection][_tokenId].seller == _msgSender(),
            "Caller != NFT Seller"
        );
        _;
    }
    // modifier to check if msg.sender is the NFT offer creator
    modifier isOfferCreator(address _collection, uint256 _tokenId) {
        require(
            offer[_collection][_tokenId][_msgSender()].buyer == _msgSender(),
            "Caller != Offer Creator"
        );
        _;
    }
    // modifier to check if NFT is listed for sale
    modifier isListed(address _collection, uint256 _tokenId) {
        require(
            tokenIdExists[_collection].contains(_tokenId),
            "NFT isn't listed for sale"
        );
        _;
    }
    // modifier to check if NFT is not listed for sale
    modifier isNotListed(address _collection, uint256 _tokenId) {
        require(
            !tokenIdExists[_collection].contains(_tokenId),
            "NFT is already listed for sale"
        );
        _;
    }
    // modifier to check if offer exists
    modifier offerAvailable(address _collection, uint256 _tokenId) {
        require(
            userOfferExists[_collection][_msgSender()].contains(_tokenId),
            "Offer doesn't exist"
        );
        _;
    }
    // modifier to check if offer doesn't exist
    modifier offerNotAvailable(address _collection, uint256 _tokenId) {
        require(
            !userOfferExists[_collection][_msgSender()].contains(_tokenId),
            "Offer already exists"
        );
        _;
    }

    // Write functions

    /**
     * @notice Internal function to delete first array element if recentlyListed array length is > 5 || if collectionRecentlyListed for the _collection param array length > 3
     * @param _collection address to pass to collectionRecentlyListed mapping, 0x0 for recentlyListed array
     * @return bool to indicate if array element was deleted
     */
    function _deleteFirstArrayElement(address _collection)
        private
        returns (bool)
    {
        if (_collection == address(0)) {
            // if (recentlyListed.length > 5) {
            delete recentlyListed[0];
            for (uint256 i; i < recentlyListed.length - 1; i++) {
                recentlyListed[i] = recentlyListed[i + 1];
            }
            recentlyListed.pop();
            return true;
            // }
        } else {
            // if (collectionRecentlyListed[_collection].length > 3) {
            delete collectionRecentlyListed[_collection][0];
            for (
                uint256 i;
                i < collectionRecentlyListed[_collection].length - 1;
                i++
            ) {
                collectionRecentlyListed[_collection][
                    i
                ] = collectionRecentlyListed[_collection][i + 1];
            }
            collectionRecentlyListed[_collection].pop();
            return true;
            // }
        }
        return false;
    }

    /**
     * @notice List an NFT for sale
     * @param _collection address of the collection
     * @param _tokenId uint256 of the tokenId
     * @param _price uint256 sale price
     */
    function list(
        address _collection,
        uint256 _tokenId,
        uint256 _price
    )
        external
        whenNotPaused
        isCollection(_collection)
        isNftOwner(_collection, _tokenId)
        isApproved(_collection, _tokenId)
        isNotListed(_collection, _tokenId)
        isPriceValid(_price)
    {
        Listing memory listing = Listing(
            _msgSender(),
            _price,
            _collection,
            _tokenId
        );
        sellNFT[_collection][_tokenId] = listing;
        tokenIdExists[_collection].add(_tokenId);
        recentlyListed.push(listing);
        collectionRecentlyListed[_collection].push(listing);
        if (recentlyListed.length > 5) {
            require(
                _deleteFirstArrayElement(address(0)),
                "Error deleting first array element"
            );
        }
        if (collectionRecentlyListed[_collection].length > 3) {
            require(
                _deleteFirstArrayElement(_collection),
                "Error deleting first array element"
            );
        }
        emit ItemListed(_msgSender(), uint32(_tokenId), _price);
    }

    /**
     * @notice Update the price of an NFT listing
     * @param _collection address of the collection
     * @param _tokenId uint256 of the tokenId
     * @param _newPrice uint256 new sale price
     * @return bool to indicate if listing was updated
     */
    function updateListing(
        address _collection,
        uint256 _tokenId,
        uint256 _newPrice
    )
        external
        isListed(_collection, _tokenId)
        whenNotPaused
        isNftOwner(_collection, _tokenId)
        isApproved(_collection, _tokenId)
        returns (bool)
    {
        sellNFT[_collection][_tokenId].price = _newPrice;
        emit ItemUpdated(_msgSender(), uint32(_tokenId), _newPrice);
        return true;
    }

    /**
     * @notice Cancel an NFT listing
     * @param _collection address of the collection
     * @param _tokenId uint256 of the tokenId
     */
    function cancelListing(address _collection, uint256 _tokenId)
        external
        isListed(_collection, _tokenId)
        nonReentrant
        isNftOwner(_collection, _tokenId)
    {
        delete (sellNFT[_collection][_tokenId]);
        tokenIdExists[_collection].remove(_tokenId);
        emit ItemDelisted(uint32(_tokenId));
    }

    /**
     * @notice Buy an NFT
     * @param _collection address of the collection
     * @param _tokenId uint256 of the tokenId
     * @param _price uint256 sale price
     */
    function buyNFT(
        address _collection,
        uint256 _tokenId,
        uint256 _price
    )
        external
        isListed(_collection, _tokenId)
        whenNotPaused
        nonReentrant
        isApproved(_collection, _tokenId)
    {
        require(
            _price == sellNFT[_collection][_tokenId].price,
            "Price mismatch"
        );
        require(
            IKRC20(USDT).allowance(_msgSender(), address(this)) >= _price,
            "Insufficient USDT allowance"
        );
        IKRC20(USDT).safeTransferFrom(
            address(msg.sender),
            address(this),
            _price
        );
        _buyNFT(_collection, _tokenId, _price);
    }

    /**
     * @notice Internal function to execute Buy NFT
     * @param _collection address of the collection
     * @param _tokenId uint256 of the tokenId
     * @param _price uint256 sale price
     */
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
            userOfferExists[_collection][_msgSender()].remove(_tokenId);
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

    /** 
        @notice Add a collection to the marketplace
        @param _collection address of the collection
        @param _collectionAddress address of the royalty fees receiver
        @param _royaltyFees uint256 of the royalty fees
    */
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

    /** 
        @notice Update a collection to the marketplace
        @param _collection address of the collection
        @param _collectionAddress address of the royalty fees receiver
        @param _royaltyFees uint256 of the royalty fees
    */
    function updateCollection(
        address _collection,
        address _collectionAddress,
        uint256 _royaltyFees
    ) external whenNotPaused isAdmin isCollection(_collection) {
        require(
            _royaltyFees >= minFees && _royaltyFees <= (maxFees - tradeFee),
            "Royalty fees are high"
        );
        collection[_collection] = Collection(
            _collectionAddress,
            _royaltyFees,
            Status.Verified
        );
        emit CollectionUpdated(_collection);
    }

    /** 
        @notice Remove a collection from the marketplace
        @param _collection address of the collection
    */
    function removeCollection(address _collection)
        external
        whenNotPaused
        isAdmin
        isCollection(_collection)
    {
        require(
            collection[_collection].status == Status.Unverified,
            "Can't remove a Verified collection"
        );
        collectionAddresses.remove(_collection);
        delete (collection[_collection]);
        emit CollectionRemoved(_collection);
    }

    /** 
        @notice Verify a collection from the marketplace
        @param _collection address of the collection
    */
    function verifyCollection(address _collection)
        external
        isAdmin
        isCollection(_collection)
    {
        Collection storage collectionStatus = collection[_collection];
        collectionStatus.status = Status.Verified;
        emit CollectionVerify(_collection);
    }

    /** 
        @notice Unverify a collection from the marketplace
        @param _collection address of the collection
    */
    function unverifyCollection(address _collection)
        external
        isAdmin
        isCollection(_collection)
    {
        Collection storage collectionStatus = collection[_collection];
        collectionStatus.status = Status.Unverified;
        emit CollectionUnverify(_collection);
    }

    /**
     * @notice Create an Offer for a NFT
     * @param _collection address to create an offer for
     * @param _tokenId uint256 of the tokenId
     * @param _value uint256 of the offer value
     * @return bool true if the offer is created successfully
     */
    function createOffer(
        address _collection,
        uint256 _tokenId,
        uint256 _value
    )
        external
        isListed(_collection, _tokenId)
        whenNotPaused
        nonReentrant
        offerNotAvailable(_collection, _tokenId)
        returns (bool)
    {
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
        userOfferExists[_collection][_msgSender()].add(_tokenId);
        offerCreator[_collection][_tokenId].add(_msgSender());
        emit OfferCreated(_msgSender(), itemOwner, _value);
        return true;
    }

    /**
     * @notice Update an Offer for a NFT
     * @param _collection address to update an offer for
     * @param _tokenId uint256 of the tokenId
     * @param _newValue uint256 of the new offer value
     * @return bool true if the offer is updated successfully
     */
    function updateOffer(
        address _collection,
        uint256 _tokenId,
        uint256 _newValue
    )
        external
        isListed(_collection, _tokenId)
        whenNotPaused
        nonReentrant
        offerAvailable(_collection, _tokenId)
        returns (bool)
    {
        require(
            IKRC20(USDT).allowance(_msgSender(), address(this)) >= _newValue,
            "Approve value first"
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

    /**
     * @notice Cancel an Offer for a NFT
     * @param _collection address to cancel an offer for
     * @param _tokenId uint256 of the tokenId
     */
    function cancelOffer(address _collection, uint256 _tokenId)
        external
        nonReentrant
        offerAvailable(_collection, _tokenId)
    {
        delete (offer[_collection][_tokenId][_msgSender()]);
        userOfferExists[_collection][_msgSender()].remove(_tokenId);
        offerCreator[_collection][_tokenId].remove(_msgSender());
        emit OfferCancelled(_msgSender(), _collection, _tokenId);
    }

    /**
     * @notice Accept an Offer for a NFT
     * @param _collection address to accept an offer for
     * @param _tokenId uint256 of the tokenId
     * @param _offerer address of the offer creator
     */
    function acceptOffer(
        address _collection,
        uint256 _tokenId,
        address _offerer
    ) external whenNotPaused nonReentrant isNftOwner(_collection, _tokenId) {
        require(
            userOfferExists[_collection][_offerer].contains(_tokenId),
            "Offer doesn't exist"
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
        userOfferExists[_collection][_offerer].remove(_tokenId);
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

    /**
     * @notice Withdraw revenue generated from the marketplace
     */
    function withdrawRevenue() external whenNotPaused nonReentrant {
        uint256 revenueGenerated = revenue[_msgSender()];
        require(revenueGenerated != 0, "N/A");
        revenue[_msgSender()] = 0;
        IKRC20(USDT).safeTransfer(_msgSender(), revenueGenerated);
        emit RevenueWithdrawn(_msgSender(), revenueGenerated);
    }

    // Proxy admin functions
    /** 
        @dev script checks for approval and delists the NFT
        @param _collection address to delist from
        @param _tokenId nft to delist
    */
    function proxyDelistToken(address _collection, uint256 _tokenId)
        external
        isProxyAdmin
        isListed(_collection, _tokenId)
        nonReentrant
    {
        IERC721 nft = IERC721(_collection);
        require(
            nft.getApproved(_tokenId) != address(this),
            "NFT is approved. Cannot delist"
        );
        delete (sellNFT[_collection][_tokenId]);
        tokenIdExists[_collection].remove(_tokenId);
        emit ItemDelisted(uint32(_tokenId));
    }

    /** 
        @dev script checks for USDT approval and removes the Offer if conditions are met
        @param _collection address to read offer from
        @param _tokenId nft to read offer delist
        @param _offerCreator address of offer Creator
    */
    function proxyRemoveOffer(
        address _collection,
        uint256 _tokenId,
        address _offerCreator
    ) external isProxyAdmin isListed(_collection, _tokenId) nonReentrant {
        require(
            userOfferExists[_collection][_offerCreator].contains(_tokenId),
            "Offer doesn't exist"
        );
        uint256 value = offer[_collection][_tokenId][_offerCreator].price;
        require(
            IKRC20(USDT).balanceOf(_offerCreator) < value,
            "Offer creator balance is sufficient"
        );
        require(
            IKRC20(USDT).allowance(_offerCreator, address(this)) < value,
            "Offer creator allowance is sufficient"
        );
        delete (offer[_collection][_tokenId][_offerCreator]);
        userOfferExists[_collection][_offerCreator].remove(_tokenId);
        offerCreator[_collection][_tokenId].remove(_offerCreator);
        emit OfferCancelled(_offerCreator, _collection, _tokenId);
    }

    //OnlyOwner function calls
    /** 
        @notice update the trade fee
        @param _newTradeFee uint8 of the new trade fee
    */
    function updateTradeFee(uint8 _newTradeFee) external whenPaused onlyOwner {
        tradeFee = _newTradeFee;
        emit TradeFeeUpdated(_newTradeFee);
    }

    /** 
        @notice update the admin address
        @param _newAdmin address of the new admin
    */
    function updateAdmin(address _newAdmin) external whenPaused onlyOwner {
        admin = _newAdmin;
        emit AdminUpdated(_newAdmin);
    }

    /** 
        @notice update the proxy admin address
        @param _newAdmin address of the new admin
    */
    function updateProxyAdmin(address _newAdmin) external whenPaused onlyOwner {
        proxyAdmin = _newAdmin;
        emit AdminUpdated(_newAdmin);
    }

    /** 
        @notice recover any ERC20 token sent to the contract
        @param _token address of the token to recover
        @param _amount amount of the token to recover
    */
    function recoverToken(address _token, uint256 _amount)
        external
        whenPaused
        onlyOwner
    {
        IKRC20(_token).safeTransfer(address(msg.sender), _amount);
        emit TokenRecovery(_token, _amount);
    }

    /** 
        @notice recover any ERC721 token sent to the contract
        @param _collection address of the collection to recover
        @param _tokenId uint256 of the tokenId to recover
    */
    function recoverNFT(address _collection, uint256 _tokenId)
        external
        whenPaused
        onlyOwner
    {
        IERC721 nft = IERC721(_collection);
        nft.safeTransferFrom(address(this), address(msg.sender), _tokenId);
        emit NFTRecovery(_collection, _tokenId);
    }

    /** 
        @notice pause the marketplace
        @param _reason string of the reason for pausing the marketplace
    */
    function pauseMarketplace(string calldata _reason)
        external
        whenNotPaused
        onlyOwner
    {
        _pause();
        emit Pause(_reason);
    }

    /** 
        @notice unpause the marketplace
        @param _reason string of the reason for unpausing the marketplace
    */
    function unpauseMarketplace(string calldata _reason)
        external
        whenPaused
        onlyOwner
    {
        _unpause();
        emit Unpause(_reason);
    }
}
