//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

struct DistantNFTsData {
    address contractAddress;
    uint256 totalSupply;
    address owner;
    string symbol;
    string name;
    string tokenURI;
    uint256 mintFee;
    uint256 maxSupply;
    uint256 maxMint;
}

contract DistantNFTs is ERC721Enumerable, Ownable {
    using Strings for uint256;
    string private baseURI;
    uint256 private maxSupply;
    string private baseExtension = ".json";
    uint256 private mintFee;
    uint256 private maxMintAmount = 1;
    bool private feeSet;

    constructor(
        string memory name,
        string memory symbol,
        string memory _baseURI,
        uint256 _maxSupply
    ) ERC721(name, symbol) {
        baseURI = _baseURI;
        maxSupply = _maxSupply;
        Ownable.transferOwnership(tx.origin);
    }

    function getBaseURI() public view returns (string memory) {
        return baseURI;
    }

    function getMintFee() public view returns (uint256) {
        return mintFee;
    }

    function getMaxSupply() public view returns (uint256) {
        return maxSupply;
    }

    function getMaxMintAmount() public view returns (uint256) {
        return maxMintAmount;
    }

    // public
    function mint(address _to, uint256 _mintAmount) public payable {
        uint256 supply = totalSupply();
        require(supply + _mintAmount <= maxSupply, "Max supply exceeded");
        require(_mintAmount > 0, "Cannot mint 0 items");
        require(_mintAmount <= maxMintAmount, "Mint amount exceeds max");
        require(
            msg.value == mintFee * _mintAmount,
            "Need to send KCS with your transaction!"
        );
        for (uint256 i = 1; i <= _mintAmount; i++) {
            _safeMint(_to, supply + i);
        }
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory currentBaseURI = getBaseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        baseExtension
                    )
                )
                : "";
    }

    // only owner
    function setmaxMintAmount(uint256 _newmaxMintAmount) public onlyOwner {
        maxMintAmount = _newmaxMintAmount;
    }

    function setCost(uint256 _fee) public onlyOwner {
        require(!feeSet, "Can only set cost once");
        feeSet = true;
        mintFee = _fee;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function withdraw() public payable onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }
}

contract DistantMinter {
    address private owner;
    DistantNFTs[] private contracts;
    uint256 private minterFee = 0 ether;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    function getMinterFee() public view returns (uint256) {
        return minterFee;
    }

    function setMinterFee(uint256 _fee) public onlyOwner returns (uint256) {
        minterFee = _fee;
        return minterFee;
    }

    function setOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }

    function claimFees() public onlyOwner returns (bool, bytes memory) {
        uint256 amount = address(this).balance;
        require(amount > 0, "No fees to claim");
        (bool sent, bytes memory detail) = owner.call{value: amount}("");
        return (sent, detail);
    }

    function getContracts()
        external
        view
        returns (address[] memory DistantNFTContracts)
    {
        uint256 length = contracts.length;
        DistantNFTContracts = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            DistantNFTContracts[i] = address(contracts[i]);
        }
        return DistantNFTContracts;
    }

    function getAllMintedDistantNFTsData()
        public
        view
        returns (DistantNFTsData[] memory allMintedNFTsData)
    {
        allMintedNFTsData = new DistantNFTsData[](contracts.length);
        for (uint256 i; i < contracts.length; i++) {
            DistantNFTsData memory data;
            DistantNFTs contractAddress = contracts[i];
            data.contractAddress = address(contractAddress);
            data.totalSupply = contractAddress.totalSupply();
            data.owner = contractAddress.owner();
            data.symbol = contractAddress.symbol();
            data.name = contractAddress.name();
            if (data.totalSupply > 0) {
                data.tokenURI = contractAddress.tokenURI(1);
            }
            data.mintFee = contractAddress.getMintFee();
            data.maxSupply = contractAddress.getMaxSupply();
            data.maxMint = contractAddress.getMaxMintAmount();
            allMintedNFTsData[i] = data;
        }
        return allMintedNFTsData;
    }

    function getDistantNFTData(DistantNFTs _address)
        public
        view
        returns (DistantNFTsData memory)
    {
        DistantNFTsData memory data;
        DistantNFTs contractAddress = _address;
        data.contractAddress = address(contractAddress);
        data.totalSupply = contractAddress.totalSupply();
        data.owner = contractAddress.owner();
        data.symbol = contractAddress.symbol();
        data.name = contractAddress.name();
        if (data.totalSupply > 0) {
            data.tokenURI = contractAddress.tokenURI(1);
        }
        data.mintFee = contractAddress.getMintFee();
        data.maxSupply = contractAddress.getMaxSupply();
        data.maxMint = contractAddress.getMaxMintAmount();
        return data;
    }

    function createContract(
        string calldata name,
        string calldata symbol,
        string calldata baseURI,
        uint256 maxSupply
    ) external payable returns (address) {
        require(msg.value == minterFee, "Pay Contract creation fee");
        DistantNFTs newContract = new DistantNFTs(
            name,
            symbol,
            baseURI,
            maxSupply
        );
        contracts.push(newContract);
        return address(newContract);
    }
}
