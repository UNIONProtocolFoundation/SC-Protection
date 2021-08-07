//---------------------------------------------------
// Copyright (c) 2020-2021 Union Protocol Foundation
//---------------------------------------------------

pragma solidity >=0.6.12;

import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "./interfaces/ISCPool.sol";
import "../../union-protocol-oc-protection/contracts/UnionERC20Pool.sol";
import "./interfaces/ISCProtections.sol";

contract UnionSCPool is UnionERC20Pool, ISCPool {


    bytes32 private ppIdentifier; // Protocol & Project ID 
    uint32 public storageversion;
    ISCProtections internal scProtectionStorage;
    uint256 public lockupPeriod;
    mapping(address => uint256) private lastProvideTimestamp;

    function version() public override view returns (uint32){
        //version in format aaa.bbb.ccc => aaa*1E6+bbb*1E3+ccc;
        return uint32(1000010);
    }

    function poolType() public override view returns (uint32){
        return uint32(3);
    }

     /**
    * returns the data of the Writer:
    *    1) total amount of BasicTokens deposited (historical value)
    *    2) total amount of BasicTokens withdrawn (historical value)
    *    3) current amount of pUNN liquidity tokens that User has on the balance.
    *    4) last deposit timestamp (sec)
    *    5) timestamp that withdrawal will be unlocked (sec)
    * @param _writer - address of the Writer's wallet. 
     */
    function getWriterDataExtended(address _writer) public override view returns (uint256, uint256, uint256) {
        return (balanceOf(_writer), lastProvideTimestamp[_writer], lastProvideTimestamp[_writer].add(lockupPeriod));
    }
    
    function initialize(address admin, address _basicToken, bytes32 _ppID, address _scProtectionStorage, string memory _description) public initializer{
        __UnionERC20Pool_init(admin,_basicToken,_description);
        storageversion = uint32(version());
        require(_scProtectionStorage != address(0), "Incorrect SCProtectionStorageAdded address specified");
        scProtectionStorage = ISCProtections(_scProtectionStorage);
        ppIdentifier = _ppID;
        lockupPeriod = 1 days;
    }

    function setLockupPeriod(uint256 value) external onlyAdmin {
        lockupPeriod = value;
    }


    modifier onlySCProtection() {
        require(msg.sender == address(scProtectionStorage), "Caller is not the SCProtections");
        _;
    }

    function onProtectionPremium(address buyer,  uint256[7] memory data) public override onlySCProtection {
        //data =[uint256 _id, uint256 _premium, uint256 _amount, uint64 _validTo, uint256 newMCR, uint256 newMCRBlockNumber, uint256 mcrIncrement]
        uint256 _id = data[0];
        require (data[2] > 0, "Invalid coverage(amount)");
        require (data[1] > 0, "Invalid premium");
        require (data[3] > block.timestamp, "Invalid _validto parameter");
        //update MCR before issuing protection
        _updateMCR(data[4], data[5], data[6]);

        lockedPremium = lockedPremium.add(data[1]);

        basicToken.safeTransferFrom(buyer, address(this), data[1]); 
        emit PoolProtectionIssued(_id, data[1], data[2], uint64(data[3]));
    }

    function unlockPremium(uint256[] calldata _ids) public override {
        uint256 totalPremiumMatured = 0;        

        for(uint i=0;i<_ids.length;i++){
            //    *  (
            //     *   [0] = protection underlying pool address,
            //     *   [1] = protection type (ppID)    
            //     *   [2] = protection amount
            //     *   [3] = protection premium 
            //     *   [4] = protection issuedOn timestamp
            //     *   [5] = protection validTo timestamp 
            //     *  )
            (, , , uint256 premium, , uint validTo) = scProtectionStorage.getProtectionData(_ids[i]);
            if(validTo < block.timestamp && premium > 0){
                scProtectionStorage.withdrawPremium(_ids[i], premium);
                totalPremiumMatured = totalPremiumMatured.add(premium);
                emit PoolProtectionPremiumUnlocked(_ids[i],premium);
                // delete protections[_ids[i]];
            }
        }

        require(lockedPremium >= totalPremiumMatured, "Pool Error: trying to unlock too much. Something went very wrong...");
        lockedPremium = lockedPremium.sub(totalPremiumMatured);

        _distributeProfit(totalPremiumMatured);
    }

    function onPayoutCoverage(uint256 _id, uint256 _premiumToUnlock, uint256 _coverageToPay, address _beneficiary) external override onlySCProtection returns (bool){
        lockedPremium = lockedPremium.sub(_premiumToUnlock);
        totalCap = totalCap.add(_premiumToUnlock);
        emit PoolProtectionPremiumUnlocked(_id,_premiumToUnlock);

        totalCap = totalCap.sub(_coverageToPay);
        basicToken.safeTransfer(_beneficiary, _coverageToPay);
        emit PoolProtectionCoveragePaid(_id, _coverageToPay, _beneficiary);
        //decrease pool capital
        return true;
    }

    function ppID() override public view returns (bytes32){
        return ppIdentifier;
    }

    /**
    * converts spefied amount of Liquidity tokens to Basic Token and returns to user (withdraw). The balance of the User (msg.sender) is decreased by specified amount of 
    * Liquidity tokens. Resulted amount of tokens are transferred to msg.sender
    * @param _requestID - request ID generated on the backend (for reference)
    * @param _amount - amount of liquidity to be withdrawn
    * @param _data - data package with withdraw quotation. The package structure provided below: 
    *       _data[0] = requestID - request ID generated on the backend (for reference)
    *       _data[1] = amount - amount of liquidity to be withdrawn
    *       _data[2] = mcr - MCR value as of mcrBlockNumber
    *       _data[3] = mcrBlockNumber - a block number MCR was calculated for
    *       _data[4] = deadline - operation deadline, timestamp in seconds
    * @param _signature - _data package signature that will be validated against whitelisted key.
    */
    function withdrawWithData(uint256 _requestID, uint256 _amount, uint256[5] memory _data, bytes memory _signature) external{
        require(lastProvideTimestamp[msg.sender].add(lockupPeriod) <= now, "Withdrawal is locked up");
        uint256 newMCR;
        uint64 newMCRBlockNumber;
        {
     
            // let requestID = data[0]; //withdrawal requestID, generated randomly by the backend. 
            // let amount = data[1]; //amount that user attempts to withdraw, provided by front-end.
            // let MCR = data[2]; // pool MCR as of "mcrBlockNumber"
            // let mcrBlockNumber = data[3];// a block number MCR was calculated at. 
            // let deadline = data[4]; // timestamp that withdraw request is valid until, in seconds. 
            
            address recovered = recoverSigner(keccak256(abi.encodePacked(_data[0], _data[1], _data[2], _data[3], _data[4])), _signature);
            require (hasRole(MCR_PROVIDER, recovered),"Data Signature invalid");
            require (_requestID == _data[0], "Incorrect data package (_requestID)");
            require (_amount == _data[1], "Incorrect data package (_amount)");
            // require (getLatestPrice() >= _data[2], "Asset current spot price went below minimum price allowed. Withdraw quotaion is no longer valid. Please try again in a while");
            require (block.timestamp <= _data[4], "quotation expired");

            newMCR = _data[2];
            newMCRBlockNumber = uint64(_data[3]);
        }

        //MCR & update MCR
        _updateMCR(newMCR,newMCRBlockNumber,0);

        _withdraw(_amount, msg.sender);
    }

    function _beforeTokenTransfer(address from, address, uint256) internal override {
        require(lastProvideTimestamp[from].add(lockupPeriod) <= now, "Withdrawal is locked up");
        require(!scProtectionStorage.isClaimLocked(address(this)), "Pool is currently locked by active claim");
    }

    function _afterDeposit(uint256 amountTokenSent, uint256 amountLiquidityGot, address sender, address holder) internal override {
        super._afterDeposit(amountTokenSent, amountLiquidityGot, sender, holder);
        lastProvideTimestamp[holder] = now;
    }

}
