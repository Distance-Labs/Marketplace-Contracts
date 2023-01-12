// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

struct Collection {
    address collectionAddress;
    uint256 royaltyFees;
    Status status;
}

struct Listing {
    address seller;
    uint256 price;
    address collection;
    uint256 tokenId;
}

interface IVoid {
    function getSupportedCollections()
        external
        view
        returns (address[] memory availableCollections);

    function getListing(address _collection, uint256 _tokenId)
        external
        view
        returns (Listing memory);

    function getCollectionData(address _collection)
        external
        view
        returns (Collection memory);
}

interface IKRC20 is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

enum Status {
    Unverified,
    Verified
}

contract AuctionHouse is
    Context,
    Ownable,
    Pausable,
    ReentrancyGuard,
    ERC721Holder
{
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;
    using SafeERC20 for IKRC20;

    address private immutable USDT; // Native ERC20 token for trades
    uint16 private tradeFee; // marketplace fee 1% == 100, 1000 == 10%
    address private admin; // marketplace controller
    address public VOID; // Marketplace Contract address for the IVoid interface

    // trade fee to be in counts of 100: 1% == 100, 10% = 1000
    constructor(
        uint16 _tradeFee,
        address _USDT,
        address _void
    ) {
        tradeFee = _tradeFee;
        admin = _msgSender();
        USDT = _USDT;
        Ownable(_msgSender());
        VOID = _void;
    }

    event AuctionStarted(
        address indexed creator,
        uint256 indexed startBidPrice,
        bytes32 indexed auctionId
    );
    event AuctionCancelled(address indexed creator, bytes32 indexed auctionId);
    event BidAccepted(
        address indexed owner,
        address indexed bidder,
        uint256 amount,
        bytes32 indexed auctionId
    );
    event BidCreated(
        address indexed bidder,
        uint256 indexed bidAmount,
        bytes32 indexed auctionId
    );
    event BidUpdated(
        address indexed bidder,
        uint256 indexed newBid,
        bytes32 indexed auctionId
    );
    event BidCancelled(address indexed bidder, bytes32 indexed auctionId);
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

    error CannotExecute();

    enum AuctionState {
        InActive,
        Active,
        Sold
    }

    mapping(address => mapping(uint256 => EnumerableSet.Bytes32Set))
        private auctionIds;
    mapping(bytes32 => EnumerableSet.AddressSet) private bidders;
    mapping(bytes32 => uint256) private auctionIdIndex;
    mapping(bytes32 => Auction) private auction;
    mapping(bytes32 => mapping(address => Bid)) private bid;
    mapping(address => uint256) private revenue;
    Auction[] private recentAuctions;
    bytes32[] private allAuctionsId;
    bytes32[] private activeAuctionsId;

    struct Bid {
        address bidder;
        uint256 bidAmount;
        bool canWithdraw;
    }

    struct Auction {
        address creator;
        address collection;
        uint256 tokenId;
        uint256 highestBid;
        address highestBidder;
        uint256 startingBid;
        uint256 endTime;
        AuctionState state;
        uint256 bidsCount;
    }

    modifier isBidValid(uint256 _price, bytes32 _auctionId) {
        require(_price > 0, "Price must be > 0");
        require(
            IKRC20(USDT).allowance(_msgSender(), address(this)) >= _price,
            "Bidder allowance is less than bid"
        );
        Auction memory readAuction = auction[_auctionId];
        require(
            _price > readAuction.startingBid,
            "Price must be greater than starting bid"
        );
        require(
            _price > readAuction.highestBid,
            "Price must be greater than highest bid"
        );
        require(
            readAuction.state == AuctionState.Active,
            "Auction is not Active"
        );
        require(readAuction.creator != _msgSender(), "Auction Creator error");
        require(
            !bidders[_auctionId].contains(_msgSender()),
            "You have an active bid"
        );
        require(block.timestamp <= readAuction.endTime, "Auction ended");
        _;
    }
    modifier isBidUpdateValid(uint256 _price, bytes32 _auctionId) {
        require(_price > 0, "Price must be > 0");
        require(
            IKRC20(USDT).allowance(_msgSender(), address(this)) >= _price,
            "Bidder allowance is less than bid"
        );
        Auction memory readAuction = auction[_auctionId];
        require(
            _price > readAuction.startingBid,
            "Price must be greater than starting bid"
        );
        require(
            _price > readAuction.highestBid,
            "Price must be greater than highest bid"
        );
        require(
            bidders[_auctionId].contains(_msgSender()),
            "You do not have an active bid"
        );
        require(
            readAuction.state == AuctionState.Active,
            "Auction is not Active"
        );
        require(block.timestamp <= readAuction.endTime, "Auction ended");
        _;
    }
    modifier canBeListed(address _collection, uint256 _tokenId) {
        Collection memory collection = IVoid(VOID).getCollectionData(
            _collection
        );
        require(
            collection.collectionAddress != address(0),
            "Collection not Listed"
        );
        Listing memory listing = IVoid(VOID).getListing(_collection, _tokenId);
        require(
            listing.collection == address(0),
            "Token Listed for fixed sale"
        );
        require(
            IERC721(_collection).ownerOf(_tokenId) == _msgSender(),
            "Caller != NFT Owner"
        );
        bytes32 auctionId = keccak256(
            abi.encodePacked(_collection, block.timestamp, _tokenId)
        ); // might remove
        require(
            auction[auctionId].state != AuctionState.Active,
            "Auction is Active"
        );
        _;
    }
    modifier canBeAccepted(bytes32 _auctionId) {
        Auction memory readAuction = auction[_auctionId];
        require(readAuction.creator == _msgSender(), "Not Creator");
        require(
            readAuction.state == AuctionState.Active,
            "Auction is not Active"
        );
        require(readAuction.highestBid > 0, "Cannot accept bid");
        _;
    }
    modifier canBeClaimed(bytes32 _auctionId) {
        Auction memory readAuction = auction[_auctionId];
        require(
            readAuction.state == AuctionState.Sold,
            "Auction is not Complete"
        );
        require(
            readAuction.highestBidder == _msgSender(),
            "Address is not highest bidder"
        );
        _;
    }
    modifier auctionCanBeCancelled(bytes32 _auctionId) {
        Auction memory readAuction = auction[_auctionId];
        require(readAuction.creator == _msgSender(), "Not Creator");
        require(
            readAuction.state == AuctionState.Active,
            "Auction is not Active"
        );
        _;
    }
    modifier bidCanBeCancelled(bytes32 _auctionId) {
        require(bidders[_auctionId].contains(_msgSender()), "Not bidder");
        require(
            auction[_auctionId].highestBidder != _msgSender(),
            "Cannot execute"
        );
        _;
    }
    modifier bidCanBeWithdrawn(bytes32 _auctionId) {
        Bid memory readBid = bid[_auctionId][_msgSender()];
        require(
            bid[_auctionId][_msgSender()].bidder == _msgSender(),
            "Not bidder"
        );
        require(
            readBid.canWithdraw == true ||
                auction[_auctionId].state == AuctionState.Sold ||
                auction[_auctionId].state == AuctionState.InActive,
            "Cannot withdraw"
        );
        _;
    }

    function getAuctionBidders(bytes32 _auctionId)
        public
        view
        returns (address[] memory biddersAddress)
    {
        uint256 length = bidders[_auctionId].length();
        biddersAddress = new address[](length);
        for (uint256 i; i < length; i++) {
            biddersAddress[i] = bidders[_auctionId].at(i);
        }
    }

    function getAuctionData(bytes32 _auctionId)
        external
        view
        returns (Auction memory)
    {
        return auction[_auctionId];
    }

    function getAllActiveAuctions()
        external
        view
        returns (Auction[] memory auctionData)
    {
        auctionData = new Auction[](activeAuctionsId.length);
        for (uint256 i; i < activeAuctionsId.length; i++) {
            auctionData[i] = auction[activeAuctionsId[i]];
        }
    }

    function getAllAuctions()
        external
        view
        returns (Auction[] memory auctionData)
    {
        auctionData = new Auction[](allAuctionsId.length);
        for (uint256 i; i < allAuctionsId.length; i++) {
            auctionData[i] = auction[allAuctionsId[i]];
        }
    }

    function getRecentAuctions()
        external
        view
        returns (Auction[] memory auctionData)
    {
        auctionData = new Auction[](recentAuctions.length);
        for (uint256 i; i < recentAuctions.length; i++) {
            auctionData[i] = recentAuctions[i];
        }
    }

    function geAllBids(bytes32 _auctionId)
        external
        view
        returns (Bid[] memory bidsData)
    {
        uint256 length = bidders[_auctionId].length();
        bidsData = new Bid[](length);
        address[] memory auctionBidders = new address[](length);
        auctionBidders = getAuctionBidders(_auctionId);
        for (uint256 i; i < length; i++) {
            bidsData[i] = bid[_auctionId][auctionBidders[i]];
        }
    }

    function getAuctionId(address _collection, uint256 _tokenId)
        external
        view
        returns (bytes32[] memory auctionsId)
    {
        uint256 length = auctionIds[_collection][_tokenId].length();
        auctionsId = new bytes32[](length);
        for (uint256 i; i < length; i++) {
            auctionsId[i] = auctionIds[_collection][_tokenId].at(i);
        }
    }

    function getAuctionIdIndex(bytes32 _auctionId)
        external
        view
        returns (uint256)
    {
        return auctionIdIndex[_auctionId];
    }

    function createAuction(
        address _collection,
        uint256 _tokenId,
        uint256 _startingBid,
        uint256 _endingTime
    ) public whenNotPaused nonReentrant canBeListed(_collection, _tokenId) {
        IERC721 nft = IERC721(_collection);
        bytes32 auctionId = keccak256(
            abi.encodePacked(_collection, block.timestamp, _tokenId)
        );
        require(
            auction[auctionId].state != AuctionState.Active,
            "Auction is Active"
        );
        nft.safeTransferFrom(_msgSender(), address(this), _tokenId);
        auction[auctionId] = Auction(
            _msgSender(),
            _collection,
            _tokenId,
            0,
            address(0),
            _startingBid,
            block.timestamp + _endingTime,
            AuctionState.Active,
            0
        );
        allAuctionsId.push(auctionId);
        auctionIdIndex[auctionId] = activeAuctionsId.length;
        activeAuctionsId.push(auctionId);
        auctionIds[_collection][_tokenId].add(auctionId);
        recentAuctions.push(
            Auction(
                _msgSender(),
                _collection,
                _tokenId,
                0,
                address(0),
                _startingBid,
                block.timestamp + _endingTime,
                AuctionState.Active,
                0
            )
        );
        _updateRecentAuctions();
        emit AuctionStarted(_msgSender(), _startingBid, auctionId);
    }

    function _updateRecentAuctions() private {
        if (recentAuctions.length > 5) {
            delete recentAuctions[0];
            for (uint256 i = 0; i < recentAuctions.length - 1; i++) {
                recentAuctions[i] = recentAuctions[i + 1];
            }
            recentAuctions.pop();
        }
    }

    function createBid(uint256 _bidValue, bytes32 _auctionId)
        public
        whenNotPaused
        nonReentrant
        isBidValid(_bidValue, _auctionId)
    {
        IKRC20(USDT).safeTransferFrom(_msgSender(), address(this), _bidValue);
        Auction storage writeAuction = auction[_auctionId];
        bid[_auctionId][_msgSender()] = Bid(_msgSender(), _bidValue, false);
        address previousBidder = writeAuction.highestBidder;
        if (previousBidder != address(0)) {
            bid[_auctionId][previousBidder].canWithdraw = true;
            emit BidCancelled(previousBidder, _auctionId);
        }
        bidders[_auctionId].add(_msgSender());
        writeAuction.highestBidder = _msgSender();
        writeAuction.highestBid = _bidValue;
        writeAuction.bidsCount += 1;
        emit BidCreated(_msgSender(), _bidValue, _auctionId);
    }

    function acceptBid(bytes32 _auctionId)
        public
        whenNotPaused
        nonReentrant
        canBeAccepted(_auctionId)
    {
        Auction storage writeAuction = auction[_auctionId];
        address _collection = writeAuction.collection;
        Collection memory collection = IVoid(VOID).getCollectionData(
            _collection
        );
        (uint256 amount, uint256 marketplaceFee, uint256 collectionFee) = _fees(
            _collection,
            writeAuction.highestBid
        );
        if (collectionFee != 0) {
            revenue[collection.collectionAddress] += collectionFee;
        }
        if (marketplaceFee != 0) {
            revenue[admin] += marketplaceFee;
        }
        writeAuction.state = AuctionState.Sold;
        bidders[_auctionId].add(writeAuction.highestBidder);
        _updateActiveAuctionIds(_auctionId);
        IKRC20(USDT).safeTransfer(_msgSender(), amount);
        emit BidAccepted(
            _msgSender(),
            writeAuction.highestBidder,
            amount,
            _auctionId
        );
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
        Collection memory collection = IVoid(VOID).getCollectionData(
            _collection
        );
        marketplaceFee = (_price * tradeFee) / 10000;
        collectionFee = (_price * collection.royaltyFees) / 10000;
        amount = _price - (marketplaceFee + collectionFee);
        return (amount, marketplaceFee, collectionFee);
    }

    function cancelAuction(bytes32 _auctionId)
        public
        auctionCanBeCancelled(_auctionId)
    {
        Auction storage writeAuction = auction[_auctionId];
        address _collection = writeAuction.collection;
        IERC721 nft = IERC721(_collection);
        writeAuction.state = AuctionState.InActive;
        nft.safeTransferFrom(address(this), _msgSender(), writeAuction.tokenId);
        _updateActiveAuctionIds(_auctionId);
        emit AuctionCancelled(_msgSender(), _auctionId);
    }

    function _updateActiveAuctionIds(bytes32 _auctionId) private {
        uint256 index = auctionIdIndex[_auctionId];
        for (uint256 i = index; i < activeAuctionsId.length; i++) {
            activeAuctionsId[index] = activeAuctionsId[index + 1];
        }
        activeAuctionsId.pop();
    }

    function cancelBid(bytes32 _auctionId)
        public
        bidCanBeCancelled(_auctionId)
    {
        bid[_auctionId][_msgSender()].canWithdraw = true;
        auction[_auctionId].bidsCount -= 1;
        bidders[_auctionId].remove(_msgSender());
        emit BidCancelled(_msgSender(), _auctionId);
    }

    function claimBidValue(bytes32 _auctionId)
        public
        bidCanBeWithdrawn(_auctionId)
    {
        Auction memory readAuction = auction[_auctionId];
        if (
            readAuction.state == AuctionState.Sold ||
            readAuction.state == AuctionState.InActive ||
            readAuction.highestBidder == _msgSender()
        ) {
            revert CannotExecute();
        } else {
            IKRC20(USDT).safeTransfer(
                _msgSender(),
                bid[_auctionId][_msgSender()].bidAmount
            );
        }
    }

    function updateBid(uint256 _newBidValue, bytes32 _auctionId)
        public
        whenNotPaused
        nonReentrant
        isBidUpdateValid(_newBidValue, _auctionId)
    {
        Bid storage writeBid = bid[_auctionId][_msgSender()];
        uint256 _bidValue = _newBidValue - writeBid.bidAmount;
        writeBid.bidAmount = _newBidValue;
        IKRC20(USDT).safeTransferFrom(_msgSender(), address(this), _bidValue);
        Auction storage writeAuction = auction[_auctionId];
        address previousBidder = writeAuction.highestBidder;
        if (previousBidder != address(0)) {
            bid[_auctionId][previousBidder].canWithdraw = true;
            emit BidCancelled(previousBidder, _auctionId);
        }
        writeAuction.highestBidder = _msgSender();
        writeAuction.highestBid = _newBidValue;
        emit BidCreated(_msgSender(), _newBidValue, _auctionId);
    }

    function claimTokenId(bytes32 _auctionId) public canBeClaimed(_auctionId) {
        Auction memory readAuction = auction[_auctionId];
        address _collection = readAuction.collection;
        IERC721 nft = IERC721(_collection);
        bidders[_auctionId].remove(_msgSender());
        nft.safeTransferFrom(
            address(this),
            readAuction.highestBidder,
            readAuction.tokenId
        );
    }

    function withdrawRevenue() external whenNotPaused nonReentrant {
        uint256 revenueGenerated = revenue[_msgSender()];
        require(revenueGenerated != 0, "N/A");
        revenue[_msgSender()] = 0;
        IKRC20(USDT).safeTransfer(_msgSender(), revenueGenerated);
        emit RevenueWithdrawn(_msgSender(), revenueGenerated);
    }

    function updateTradeFee(uint8 _newTradeFee) external whenPaused onlyOwner {
        tradeFee = _newTradeFee;
        emit TradeFeeUpdated(_newTradeFee);
    }

    function updateAdmin(address _newAdmin) external whenPaused onlyOwner {
        admin = _newAdmin;
        emit AdminUpdated(_newAdmin);
    }

    function clearAuctions(uint256 max) public {
        require(_msgSender() == admin, "Not Admin");
        uint256 length = allAuctionsId.length - max;
        require(allAuctionsId.length > 1, "Cannot execute");
        for (uint256 i; i < length; i++) {
            allAuctionsId[i] = allAuctionsId[i + max];
        }
        while (allAuctionsId.length >= length) {
            allAuctionsId.pop();
        }
    }

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
