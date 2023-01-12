# Marketplace-Contracts
Distant Finance NFT marketplace contracts


This repository has been created to serve as a comprehensive source for all Solidity files that have been utilized in the development of our smart contracts for the NFT (non-fungible token) Marketplace. 
The NFT Marketplace is a cutting-edge platform that allows for the buying, selling, and trading of unique digital assets, and it requires a robust set of smart contracts to ensure its smooth operation. 
The Solidity files in this repository have been carefully crafted to meet the specific requirements of the NFT Marketplace, and some have been rigorously tested to ensure their reliability and security and some deployed to production.

The repository includes a variety of different smart contracts that are essential to the functioning of the NFT Marketplace. 
One of the most important contracts is the NFT Minter contract, which is responsible for creating and issuing unique digital assets to users. This contract is designed to be highly secure, and it employs advanced cryptographic techniques to ensure the integrity of the NFTs it mints. 
Another important contract is the Drops Contract, which is used to manage the distribution of digital assets to users. This contract is also designed to be highly secure, and it employs a variety of different mechanisms to prevent unauthorized access and manipulation.

In addition to the NFT Minter and Drops Contract, the repository also includes the Auction House Contract, which is used to facilitate the buying and selling of digital assets through a decentralized auction process. This contract is designed to be highly flexible and customizable, and it allows users to create and participate in auctions for a wide variety of different types of NFTs. 
The repository also includes both version 1 and version 2 of the Marketplace Contract, which is used to manage the overall operation of the NFT Marketplace. These contracts are designed in mind to be highly scalable and efficient, and they employ a variety of different mechanisms to ensure the smooth and efficient operation of the marketplace.

In conclusion, this repository serves as a vital resource for the development and operation of the NFT Marketplace. It contains all the Solidity files that are necessary to build a robust, secure and efficient platform for buying, selling and trading of unique digital assets. The contracts in this repository have been thoroughly tested and optimized to ensure their reliability and security, and they will continue to be updated and improved as the NFT Marketplace evolves.


The Marketplace v1 --beta
The Marketplace v1 (beta) is a production-ready smart contract for our NFT (non-fungible token) marketplace. This contract has been specifically designed to meet the requirements of the KuCoin Community Chain and is currently fully functional on this platform.

The Marketplace v1 (beta) contract has undergone rigorous testing and optimization to ensure its reliability and security. 
At present, there are no known vulnerabilities in this contract and a number of low gas optimizations have been implemented to minimize the cost of executing transactions on the contract. 
However, it should be noted that this is still a beta version of the contract and further improvements and bug fixes may be made before the final iteration of the marketplace is released.

The NFT marketplace is a revolutionary platform that allows for the buying, selling, and trading of unique digital assets. 
It requires a robust set of smart contracts to ensure its smooth operation, and the Marketplace v1 (beta) contract plays a crucial role in this process. 
It manages the overall operation of the marketplace, and it is responsible for facilitating the buying and selling of NFTs through a decentralized process. The contract is designed to be highly flexible and customizable extending its stack to the Auction house.

Overall, the Marketplace v1 (beta) contract is a vital component of the NFT marketplace, and it is designed to provide a secure and efficient platform for buying, selling and trading of unique digital assets. 
While this is a beta version of the contract, it has been thoroughly tested and optimized to ensure its reliability and security, and it will continue to be updated and improved as the NFT Marketplace evolves.


The Marketplace V2 --beta ---deprecated
The Marketplace V2 (beta) is a deprecated smart contract that was previously intended for use as a production-ready version for our NFT (non-fungible token) marketplace, however, it has since been superseded by the final version of the marketplace. This Solidity file contains the contract code for the beta version of the V2 marketplace, which was under development before it was deprecated.

The upcoming final iteration of the Distant Marketplace will incorporate much of the code from this beta version, but with a few significant changes. One of the major changes is the replacement of USDT with WKCS and KCS as the only means of exchange on the marketplace. This decision was made in order to streamline the marketplace and make it more user-friendly. Additionally, there will be a number of gas optimization techniques employed in the final version of the marketplace, and redundant code that was used to store data directly into the smart contract will be removed. Instead, a graph node will be implemented to reduce the gas expenses incurred by users.

It should be noted that this beta version of the Marketplace V2 contract is no longer in use and should not be considered reliable or secure. The final version of the Distant Marketplace will provide a more robust and efficient platform for buying, selling, and trading unique digital assets. The team is committed to ensuring the security and reliability of the marketplace and will continue to make improvements and optimizations to the platform.


The Qatar Event Contract
The Qatar Event Contract is a smart contract that was developed for a prediction game during the FIFA 2022 World Cup event. The contract was designed to allow users to make predictions about the outcome of the matches and potentially win prizes.

However, the contract was later cancelled abruptly due to a number of factors, including issues with gas optimizations and incorrect mathematical formulas that resulted in functions failing. These technical issues were identified during testing, and it was determined that they would not be able to be resolved in a timely manner before the event. As a result, the decision was made to cancel the contract and the prediction game.

It should be noted that this contract should not be considered reliable or secure, as it has not undergone the necessary testing and optimizations to ensure its functionality and security. This contract should not be used for any prediction game in the future. The team is committed to providing a high-quality service to our users and will strive to identify and resolve any technical issues as soon as possible to ensure the smooth operation of any future events.


NFT Collection Minter 
The NFT Collection Minter is a smart contract that is utilized to mint NFT Collections, which are used to mint fully-fledged NFT contracts. This contract allows users to create unique collections of digital assets, and it employs advanced cryptographic techniques to ensure the integrity of the collections it mints.

However, the team behind the contract has recently begun to re-evaluate the use of this contract and is considering a potential move to shut it down and release a standalone NFT Minter contract. The idea behind this change is to streamline the minting process and to make it more user-friendly. Additionally, a separate drops contract may be implemented to mint collections according to specific specifications.

It should be noted that this decision is still under consideration and has not been finalized. The team is constantly evaluating the functionality and usability of the contract to ensure it is meeting the needs of our users. Any changes made to the contract will be communicated to users in a timely manner.


The Auction Contract file
The Auction contract is implemented with checks in compliance with our Marketplace contract. It has not undergone any tests so may have a long list of vulnerabilities
We will update the code once tests has started
