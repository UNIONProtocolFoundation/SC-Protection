//---------------------------------------------------
// Copyright (c) 2020-2021 Union Protocol Foundation
// SPDX-License-Identifier: GPL-2.0-or-later
//---------------------------------------------------

pragma solidity >=0.6.12;

import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/proxy/Initializable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/math/SafeMathUpgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/token/ERC20/SafeERC20Upgradeable.sol";
import "../../union-protocol-oc-protection/contracts/libraries/SignLib.sol";

import "../../union-protocol-oc-protection/contracts/interfaces/IUUNNRegistry.sol";
import "./interfaces/ISCPool.sol";
import "./interfaces/ISCProtections.sol";
import "./interfaces/ISCPClaims.sol";


contract SCProtections is Initializable, AccessControlUpgradeable, PausableUpgradeable, SignLib, ISCProtections{

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IUUNNRegistry private uunn;

    bytes32 public constant PROTECTION_PREMIUM_DATA_PROVIDER = keccak256("PROTECTION_PREMIUM_DATA_PROVIDER");//premium provider
    uint32 storageVersion;

    struct SCProtectionData {
        ISCPool pool;
        uint256 timelimits; //IssuedOn_ValidTo
        uint256 amount;
        uint256 premium;
        uint256 coveragePaid;
    }

    struct SCProtectionDocuments {
        //ERC1643
        mapping(bytes32 => Document) document;
        bytes32[] docNames;
        mapping(bytes32 => uint256) docIndexes;
    } 

    struct Document {
        bytes32 docHash; // Hash of the document
        uint256 lastModified; // Timestamp at which document details was last modified
        string uri; // URI of the document that exist off-chain
    }

    mapping(uint256 => SCProtectionDocuments) internal protectionDocuments;
    mapping(uint256 => SCProtectionData) internal protections;
    mapping (bytes32 => address) internal scProtectionPools; //pool by protocol ID.
    ISCPClaims internal claimStorage;
    mapping(address => uint64[]) activeClaimsForPool; 
    uint8 public maxActiveClaimsPerPoolAllowed;

    event ProtocolPoolRegistered(bytes32 indexed ppID, address pool);
    event SCProtectionCreated(address indexed receiver, uint256 tokenId, address pool, uint256 amount, uint issuedOn, uint validTo, uint256 premium);
    event Exercised(uint256 indexed id, uint256 amount, uint256 profit);
    event DocumentRemoved(uint256 indexed id, bytes32 indexed _name, string _uri, bytes32 _documentHash);
    event DocumentUpdated(uint256 indexed id, bytes32 indexed _name, string _uri, bytes32 _documentHash);
    
    function version() public override pure returns (uint32){
        //version in format aaa.bbb.ccc => aaa*1E6+bbb*1E3+ccc;
        return uint32(1000010);
    }

    function initialize(address _admin, address _uunn, address _claimStorage) public initializer{
        __AccessControl_init();
        __Pausable_init_unchained();
        require(_uunn != address(0), "Incorrect uUNNToken address specified");
        require(_claimStorage != address(0), "Incorrect claimStorage address specified");
        uunn = IUUNNRegistry(_uunn);
        claimStorage = ISCPClaims(_claimStorage);
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        storageVersion = version();
        maxActiveClaimsPerPoolAllowed = uint8(10);
    }

    /**
    * @dev Throws if called by any account other than the one with the Admin role granted.
    */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not the Admin");
        _;
    }

    /**
    * set contract on hold. Paused contract doesn't accepts Deposits but allows to withdraw funds. 
     */
    function pause() onlyAdmin public {
        super._pause();
    }
    /**
    * unpause the contract (enable deposit operations)
     */
    function unpause() onlyAdmin public {
        super._unpause();
    }

    /** buy protection function. Creates protection ERC721 token and funds appropriate pool with premium. 
    * @param data - data package with withdraw quotation. The package structure provided below: 
    *       data[0] = tokenid - protection ERC721 token identifier (UUID)
    *       data[1] = premium - amount of premium tokens to be transferred to pool (protection cost)
    *       data[2] = validTo - protection validTo parameter, timestamp (protection will be valid until this timestamp)
    *       data[3] = amount - the underlying protected asset amount (with appropriate decimals)
    *       data[4] = poolAddress - address of the underlying pool, that will be backing the protection
    *       data[5] = mcr - MCR value as of mcrBlockNumber
    *       data[6] = mcrBlockNumber - a block number MCR was calculated for
    *       data[7] = mcrIncrement - an MCR increment. The amount of capital has to be reserved under MCR to cover this individual protection (that will be issued within transaction)
    *       data[8] = deadline - operation deadline, timestamp in seconds
    * @param signature - data package signature that will be validated against whitelisted key.
    * @param deadline - operation deadline in seconds
    */
    function create(uint256[9] memory data, bytes memory signature, uint256 deadline) public override whenNotPaused returns (address){
        return createTo(data, signature, msg.sender, deadline);
    }


    /** buy protection function. Creates protection ERC721 token and funds appropriate pool with premium. Protection token is assigned in address of erc721Receiver    
    * @param data - data package with withdraw quotation. The package structure provided below: 
    *       data[0] = tokenid - protection ERC721 token identifier (UUID)
    *       data[1] = premium - amount of premium tokens to be transferred to pool (protection cost)
    *       data[2] = validTo - protection validTo parameter, timestamp (protection will be valid until this timestamp)
    *       data[3] = amount - the underlying protected asset amount (with appropriate decimals)
    *       data[4] = poolAddress - address of the underlying pool, that will be backing the protection
    *       data[5] = mcr - MCR value as of mcrBlockNumber
    *       data[6] = mcrBlockNumber - a block number MCR was calculated for
    *       data[7] = mcrIncrement - an MCR increment. The amount of capital has to be reserved under MCR to cover this individual protection (that will be issued within transaction)
    *       data[8] = deadline - operation deadline, timestamp in seconds
    * @param signature - data package signature that will be validated against whitelisted key.
    * @param erc721Receiver - address of the Protection ERC721 token receiver. 
    * @param deadline - operation deadline in seconds
    */
    function createTo(uint256[9] memory data, bytes memory signature, address erc721Receiver, uint256 deadline) public override whenNotPaused returns (address){
        require (block.timestamp <= deadline, "Transaction expired");
        address recovered = recoverSigner(keccak256(abi.encodePacked(data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7], data[8])), signature);
        //tokenID, premium, validTo, amount
        // uint256[6] memory ocdata = [data[0],data[1],validTo,amount,strike, ISCPool(pool).getLatestPrice()];
        {
            require (hasRole(PROTECTION_PREMIUM_DATA_PROVIDER, recovered),"Data Signature invalid");
            require (block.timestamp <= data[8], "Quotation expired");
            
            // send premium to the pool contract
            IERC20Upgradeable(ISCPool(address(data[4])).getBasicToken()).safeTransferFrom(msg.sender, address(this), data[1]);
            IERC20Upgradeable(ISCPool(address(data[4])).getBasicToken()).approve(address(data[4]), data[1]);
            //register protection in pool
            //data =[uint256 _id, uint256 _premium, uint256 _amount, uint64 _validTo, uint256 newMCR, uint256 newMCRBlockNumber, uint256 mcrIncrement]
            ISCPool(address(data[4])).onProtectionPremium(address(this), [data[0],data[1],data[3],data[2],data[5],data[6],data[7]]);
        }

        {
            uint256 timelimits = (block.timestamp << 64).add(data[2]);

        // ISCPool pool;
        // uint256 timelimits; //IssuedOn_ValidTo
        // uint256 amount;
        // uint256 premium;
        // uint256 coveragePaid;
        // uint8 status;

            protections[data[0]] = SCProtectionData(ISCPool(address(data[4])), timelimits, data[3], data[1], 0);
            uunn.mint(data[0], address(this), erc721Receiver);

        }
        emit SCProtectionCreated(erc721Receiver, data[0], address(data[4]), data[3], now, data[2], data[1]);

        return address(this);

    }

    function withdrawPremium(uint256 _id, uint256 _premium) external override {
        require (msg.sender == address(protections[_id].pool) && msg.sender != address(0),"Premium can be withdrawn by backed pool only");
        require (protections[_id].premium >= _premium, "Not enough premium left");
        protections[_id].premium = protections[_id].premium.sub(_premium);
    }

    function setActiveSCProtectionPoolAddress(bytes32 _ppID, address _value) public onlyAdmin {
        scProtectionPools[_ppID] = _value;
        emit ProtocolPoolRegistered(_ppID, _value);
    }

    function setMaxActiveClaimsPerPool(uint8 _claimsAmt) public onlyAdmin {
        maxActiveClaimsPerPoolAllowed = _claimsAmt;
    }

    function getActiveSCProtectionPool(bytes32 _ppID) external override view returns (address) {
        return scProtectionPools[_ppID];
    }

    function exercise(uint256 _id, uint64 _timestamp) public {
        //get protocol ID;
        require(address(protections[_id].pool)!=address(0), "Pool not registered");
        uint256 validTo = protections[_id].timelimits & 0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF;
        uint256 issuedOn = (protections[_id].timelimits >> 64) & 0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF;
        bytes32 ppID = protections[_id].pool.ppID();
        //get Claim status for protocol and timestamp;
        (uint8 claimStatus, uint8 payoutPercent, ,address claimPool, uint64 lastStatusUpdateTimestamp) = claimStorage.getClaimData(ppID, _timestamp);
        require (claimStatus > 0, "Claim not found");
        require (claimStatus == uint8(ISCPClaims.ClaimStatus.Approved), "Can't exercise with unapproved claim");
        require (claimPool == address(protections[_id].pool), "Claim pool reference doesn't match protection pool");
        require (_timestamp >= issuedOn, "Protection issued date is greater then claim filled date. Can't exercise such protection");
        require (_timestamp <= validTo, "Protection expired by the Claim Event date");
        require (lastStatusUpdateTimestamp + claimStorage.protectionPayoutPeriod() >= uint64(block.timestamp), "Protection payout period expired");
        //amount of coverage to pay is regulated by claim
        uint amountToPay = protections[_id].amount.mul(uint256(payoutPercent)).div(100);

        uint256 _amount = protections[_id].amount;
        protections[_id].amount = 0;//deactivate protection
        protections[_id].premium = 0;//set premium unlocked
        
        protections[_id].pool.onPayoutCoverage(_id, protections[_id].premium, amountToPay, msg.sender);

        emit Exercised(_id, _amount, amountToPay);
    }

    function setClaimLock(address _pool, uint64 _timestamp) public override {
        require (msg.sender == address(claimStorage), "This function is for claimStorage only");
        activeClaimsForPool[_pool].push(_timestamp);
        require (activeClaimsForPool[_pool].length <= maxActiveClaimsPerPoolAllowed, "Too many claims");
    }

    function releaseClaimLock(address _pool, uint64 _timestamp) public override {
        require (msg.sender == address(claimStorage), "This function is for claimStorage only");
        bool claimFound = false;
        if(activeClaimsForPool[_pool].length > 1){
            for(uint i=0; i<activeClaimsForPool[_pool].length; i++){
                if(activeClaimsForPool[_pool][i] == _timestamp) {
                    //move the last array item to removed item place
                    if(i < activeClaimsForPool[_pool].length - 1){
                        activeClaimsForPool[_pool][i] = activeClaimsForPool[_pool][activeClaimsForPool[_pool].length - 1];
                    }
                    claimFound = true;
                    break;
                }
            }
        } else {
            claimFound = activeClaimsForPool[_pool][0] == _timestamp;
        }
        require (claimFound, "Active claim not found for requested pool");
        activeClaimsForPool[_pool].pop();
    }

    function isClaimLocked(address _pool) public override view returns (bool){
        if(activeClaimsForPool[_pool].length == 0)
            return false;
        require (ISCPool(_pool).poolType() == 3, "Incorrect pool type");
        bytes32 _ppID = ISCPool(_pool).ppID();
        //assuming amount of active claims will be low
        for(uint i=0; i<activeClaimsForPool[_pool].length; i++){
            (uint8 claimStatus, , , , uint64 lastStatusUpdateTimestamp) = claimStorage.getClaimData(_ppID, activeClaimsForPool[_pool][i]);
            if(claimStatus == uint8(ISCPClaims.ClaimStatus.Approved)){
                if( lastStatusUpdateTimestamp + claimStorage.protectionPayoutPeriod() >= uint64(block.timestamp))
                    return true;
            } else {
                if (claimStatus == uint8(ISCPClaims.ClaimStatus.New) || claimStatus == uint8(ISCPClaims.ClaimStatus.InReview))
                    return true;
            }
        }
        return false;
    }

    /** returns individual SC-P data for the protection specified by id
    * @param id - protection tokenID
    * @return tuple 
    *  (
    *   [0] = protection underlying pool address,
    *   [1] = protection type (ppID)    
    *   [2] = protection amount
    *   [3] = protection premium 
    *   [4] = protection issuedOn timestamp
    *   [5] = protection validTo timestamp
    *  )
    */
    function getProtectionData(uint256 id) public override view returns (address, bytes32, uint256, uint256, uint, uint){
        require (address(protections[id].pool) != address(0), "Protection with specified id doesn't exist");
        return (
            address(protections[id].pool),
            protections[id].pool.ppID(),
            protections[id].amount,
            protections[id].premium,
            (protections[id].timelimits >> 64) & 0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF,
            protections[id].timelimits & 0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF
        );
    }

    function setDocument(
        uint256 id,
        bytes32 name,
        string calldata uri,
        bytes32 documentHash
    )
        external 
    {
        require(msg.sender == uunn.ownerOf(id), "Caller is not the Owner of Protection");
        require(name != bytes32(0), "Bad name");
        require(bytes(uri).length > 0, "Bad uri");

        if (protectionDocuments[id].document[name].lastModified == uint256(0)) {
            protectionDocuments[id].docNames.push(name);
            protectionDocuments[id].docIndexes[name] = protectionDocuments[id].docNames.length;
        }
        protectionDocuments[id].document[name] = Document(documentHash, now, uri);
        emit DocumentUpdated(id, name, uri, documentHash);
    }

     /**
     * @notice Used to remove an existing document from the contract by giving the name of the document.
     * @dev Can only be executed by the owner of the contract.
     * @param name Name of the document. It should be unique always
     */
    function removeDocument(
        uint256 id,
        bytes32 name
    )
        external 
    {
        require(msg.sender == uunn.ownerOf(id), "Caller is not the Owner of Protection");
        require(protectionDocuments[id].document[name].lastModified != uint256(0), "Not existed");
        uint256 index = protectionDocuments[id].docIndexes[name] - 1;
        if (index != protectionDocuments[id].docNames.length - 1) {
            protectionDocuments[id].docNames[index] = protectionDocuments[id].docNames[protectionDocuments[id].docNames.length - 1];
            protectionDocuments[id].docIndexes[protectionDocuments[id].docNames[index]] = index + 1;
        }
        protectionDocuments[id].docNames.pop();
        emit DocumentRemoved(id, name, protectionDocuments[id].document[name].uri, protectionDocuments[id].document[name].docHash);
        delete protectionDocuments[id].document[name];
    }

        /**
     * @notice Used to return the details of a document with a known name (`bytes32`).
     * @param _name Name of the document
     * @return string The URI associated with the document.
     * @return bytes32 The hash (of the contents) of the document.
     * @return uint256 the timestamp at which the document was last modified.
     */
    function getDocument(uint256 id, bytes32 _name) external view returns (string memory, bytes32, uint256) {
        return (
            protectionDocuments[id].document[_name].uri,
            protectionDocuments[id].document[_name].docHash,
            protectionDocuments[id].document[_name].lastModified
        );
    }

    /**
     * @notice Used to retrieve a full list of documents attached to the smart contract.
     * @return bytes32 List of all documents names present in the contract.
     */
    function getAllDocuments(uint256 id) external view returns (bytes32[] memory) {
        return protectionDocuments[id].docNames;
    }

  
}
