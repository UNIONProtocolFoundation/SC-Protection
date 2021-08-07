//---------------------------------------------------
// Copyright (c) 2020-2021 Union Protocol Foundation
//---------------------------------------------------

pragma solidity >=0.6.12;

import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/proxy/Initializable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/math/SafeMathUpgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "../../union-protocol-oc-protection/openzeppelin-contracts-upgradeable/contracts/token/ERC20/SafeERC20Upgradeable.sol";

import "./interfaces/ISCProtections.sol";
import "./interfaces/ISCPClaims.sol";
import "./interfaces/ISCPool.sol";

contract SCPClaims is Initializable, AccessControlUpgradeable, PausableUpgradeable, ISCPClaims{

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    bytes32 public constant CLAIM_MANAGER = keccak256("CLAIM_MANAGER");
    uint64 internal claimCreateAmount; //without decimals!!!
    uint64 internal duplicationMultiplier;
    uint64 public override protectionPayoutPeriod; //time period a user is allowed to exercise his/her protection with a Approved Claim
    ISCProtections scProtections;
    mapping(bytes32 => mapping(uint64 => SCProtectionClaim)) internal claims;
    address public feesCollectorAddress; 
    uint64 internal claimAppealAmount; //without decimals!!!
    uint64 public override challengePeriod; //time period a user is allowed to Appeal Rejected claim
    uint64 public override claimFillPeriod; //time period a user is allowed to fill a claim since incident time
    
    event ClaimFilled(address indexed creator, bytes32 indexed _ppID, uint64 indexed _timestamp, address _pool, uint256 _fee);
    event ClaimFeeRefunded(address indexed creator, bytes32 indexed _ppID, uint64 indexed _timestamp, uint256 claimFeeRefunded);
    event ClaimStatusChanged(bytes32 indexed _ppID, uint64 indexed _timestamp, uint8 oldStatus, uint8 newStatus);
    event ClaimApproved(bytes32 indexed _ppID, uint64 indexed _timestamp, uint8 payAmountPercent);
    event ClaimFeeDistributed(bytes32 indexed _ppID, uint64 indexed _timestamp, uint256 claimFeesDistributed);
    
    struct SCProtectionClaim {
        ISCPool pool;
        address[] claimers;
        mapping (address => uint256) claimPayments;
        uint8 payAmountPercent;
        uint64 lastStatusUpdateTimestamp;
        ClaimStatus status;
    }
    
    function version() public pure returns (uint32){
        //version in format aaa.bbb.ccc => aaa*1E6+bbb*1E3+ccc;
        return uint32(1000010);
    }

    function initialize(address _admin, address _scProtections) public initializer{
        __AccessControl_init();
        __Pausable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        require(_scProtections != address(0), "Incorrect scProtections address");
        scProtections = ISCProtections(_scProtections);
        claimCreateAmount = 10;
        claimAppealAmount = 25;
        duplicationMultiplier = 5;
        protectionPayoutPeriod = 3 days;
        challengePeriod = 1 days;
        claimFillPeriod = 30 days;
        feesCollectorAddress = address(this); //make it safe by default
    }

    /**
    * @dev Throws if called by any account other than the one with the Admin role granted.
    */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not the Admin");
        _;
    }

     /**
    * @dev Throws if called by any account other than the one with the Claim Manager role granted.
    */
    modifier onlyClaimManager() {
        require(hasRole(CLAIM_MANAGER, msg.sender), "Caller is not Claim Manager");
        _;
    }

    function setClaimingParams(uint64 _createPaymentAmt, uint64 _duplicationMultiplier, uint64 _appealPaymentAmt) public onlyAdmin {
        duplicationMultiplier = _duplicationMultiplier;
        claimCreateAmount = _createPaymentAmt;
        claimAppealAmount = _appealPaymentAmt;
    }


    function setProtectionPayoutPeriod(uint64 _protectionPayoutPeriod) public onlyAdmin {
        protectionPayoutPeriod = _protectionPayoutPeriod;
    }

    function setChallengePeriod(uint64 _challengePeriod) public onlyAdmin {
        challengePeriod = _challengePeriod;
    }

    function setClaimFillPeriod(uint64 _claimFillPeriod) public onlyAdmin {
        claimFillPeriod = _claimFillPeriod;
    }

    function setFeesCollectorAddress(address _target) public onlyAdmin {
        require(_target != address(0), "Incorrect address specified");
        feesCollectorAddress = _target;
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

    function fillClaim(bytes32 _ppID, uint64 _timestamp) public override whenNotPaused {
        address poolAddress = scProtections.getActiveSCProtectionPool(_ppID);
        require(poolAddress != address(0),"There is no SCPool for specified protocol");
        ISCPool pool = ISCPool(poolAddress);
        _fillClaim(pool, _timestamp);
    }

    function fillClaimForPool(address _poolAddress, uint64 _timestamp) public override whenNotPaused{
        require(_poolAddress != address(0),"Pool address incorrect");
        ISCPool pool = ISCPool(_poolAddress);
        _fillClaim(pool, _timestamp);
    }

    function claimFeeRefund(bytes32 _ppID, uint64 _timestamp) public override whenNotPaused {
        require (claims[_ppID][_timestamp].status == ClaimStatus.Approved, "Refund is available for Approved claims only");
        uint256 claimingFeePaid = claims[_ppID][_timestamp].claimPayments[msg.sender];
        if(claimingFeePaid > 0){
            claims[_ppID][_timestamp].claimPayments[msg.sender] = 0;
            IERC20Upgradeable(claims[_ppID][_timestamp].pool.getBasicToken()).safeTransfer(msg.sender, claimingFeePaid);
            emit ClaimFeeRefunded(msg.sender, _ppID, _timestamp, claimingFeePaid);
        }
    }

    function distributeClaimFee(bytes32 _ppID, uint64 _timestamp) public override whenNotPaused {
        require (claims[_ppID][_timestamp].status == ClaimStatus.Rejected
            // && (dateRejected > Appeal timeout)
            || claims[_ppID][_timestamp].status == ClaimStatus.AppealRejected, "Fees distribution is available for terminal states only");

        uint256 totalFeesPaid = 0;
        for (uint i=0;i < claims[_ppID][_timestamp].claimers.length; i++){
            address claimer = claims[_ppID][_timestamp].claimers[i];
            totalFeesPaid = totalFeesPaid.add(claims[_ppID][_timestamp].claimPayments[claimer]);
        }

        claims[_ppID][_timestamp].status = ClaimStatus.FeesCollected;

        IERC20Upgradeable(claims[_ppID][_timestamp].pool.getBasicToken()).safeTransfer(feesCollectorAddress, totalFeesPaid);
        
        emit ClaimFeeDistributed(_ppID, _timestamp, totalFeesPaid);
    }

    function setClaimInReview(bytes32 _ppID, uint64 _timestamp) public override onlyClaimManager whenNotPaused{
        ClaimStatus status = claims[_ppID][_timestamp].status;
        require (uint8(status) > 0, "Claim not found");
        require (status == ClaimStatus.New, "Incorrect claim status");
        claims[_ppID][_timestamp].status = ClaimStatus.InReview;
        claims[_ppID][_timestamp].lastStatusUpdateTimestamp = uint64(block.timestamp);
        emit ClaimStatusChanged(_ppID, _timestamp, uint8(ClaimStatus.New), uint8(ClaimStatus.InReview));
    }

    function setClaimApproved(bytes32 _ppID, uint64 _timestamp, uint8 _payAmountPercentage) public override onlyClaimManager whenNotPaused{
        ClaimStatus status = claims[_ppID][_timestamp].status;
        require (uint8(status) > 0, "Claim not found");
        require (status == ClaimStatus.InReview || status == ClaimStatus.Appeal , "Incorrect claim status");
        require (_payAmountPercentage > 0 && _payAmountPercentage <= 100, "Incorrect payout percentage");
        claims[_ppID][_timestamp].status = ClaimStatus.Approved;
        claims[_ppID][_timestamp].payAmountPercent = _payAmountPercentage;
        claims[_ppID][_timestamp].lastStatusUpdateTimestamp = uint64(block.timestamp);
        emit ClaimStatusChanged(_ppID, _timestamp, uint8(status), uint8(ClaimStatus.Approved));
        emit ClaimApproved(_ppID, _timestamp, _payAmountPercentage);
    }

    function setClaimRejected(bytes32 _ppID, uint64 _timestamp) public override onlyClaimManager whenNotPaused{
        ClaimStatus status = claims[_ppID][_timestamp].status;
        require (uint8(status) > 0, "Claim not found");
        require (status == ClaimStatus.InReview, "Incorrect claim status");
        claims[_ppID][_timestamp].status = ClaimStatus.Rejected;
        claims[_ppID][_timestamp].lastStatusUpdateTimestamp = uint64(block.timestamp);
        scProtections.releaseClaimLock(address(claims[_ppID][_timestamp].pool), _timestamp);
        emit ClaimStatusChanged(_ppID, _timestamp, uint8(ClaimStatus.InReview), uint8(ClaimStatus.Rejected));
    }

    function setClaimAppeal(bytes32 _ppID, uint64 _timestamp) public override whenNotPaused{
        ClaimStatus status = claims[_ppID][_timestamp].status;
        require (uint8(status) > 0, "Claim not found");
        require (status == ClaimStatus.Rejected, "Incorrect claim status");
        require (claims[_ppID][_timestamp].lastStatusUpdateTimestamp + challengePeriod >= uint64(block.timestamp), "Challenge period expired");
        uint256 claimFillPayment = _nextClaimFillPayment(_ppID, _timestamp, claims[_ppID][_timestamp].pool);

        claims[_ppID][_timestamp].claimers.push(msg.sender);
        claims[_ppID][_timestamp].claimPayments[msg.sender] = claims[_ppID][_timestamp].claimPayments[msg.sender].add(claimFillPayment);
        claims[_ppID][_timestamp].status = ClaimStatus.Appeal;
        claims[_ppID][_timestamp].lastStatusUpdateTimestamp = uint64(block.timestamp);
        scProtections.setClaimLock(address(claims[_ppID][_timestamp].pool), _timestamp);

        IERC20Upgradeable(claims[_ppID][_timestamp].pool.getBasicToken()).safeTransferFrom(msg.sender, address(this), claimFillPayment);

        emit ClaimStatusChanged(_ppID, _timestamp, uint8(ClaimStatus.Rejected), uint8(ClaimStatus.Appeal));
    }

    function setClaimAppealRejected(bytes32 _ppID, uint64 _timestamp) public override onlyClaimManager whenNotPaused{
        ClaimStatus status = claims[_ppID][_timestamp].status;
        require (uint8(status) > 0, "Claim not found");
        require (status == ClaimStatus.Appeal, "Incorrect claim status");
        claims[_ppID][_timestamp].status = ClaimStatus.AppealRejected;
        claims[_ppID][_timestamp].lastStatusUpdateTimestamp = uint64(block.timestamp);
        scProtections.releaseClaimLock(address(claims[_ppID][_timestamp].pool), _timestamp);
        emit ClaimStatusChanged(_ppID, _timestamp, uint8(ClaimStatus.Appeal), uint8(ClaimStatus.AppealRejected));
    }

    function releaseLockOnExpiredClaim(bytes32 _ppID, uint64 _timestamp) public override whenNotPaused {
        ClaimStatus status = claims[_ppID][_timestamp].status;
        require (uint8(status) > 0, "Claim not found");
        require (status == ClaimStatus.Approved, "Incorrect claim status");
        require (claims[_ppID][_timestamp].lastStatusUpdateTimestamp + protectionPayoutPeriod < uint64(block.timestamp), "Payout period is not expired yet");
        scProtections.releaseClaimLock(address(claims[_ppID][_timestamp].pool), _timestamp);
    }

    function getNextClaimFillPayment(bytes32 _ppID, uint64 _timestamp) public override view returns (uint256){
        address poolAddress = scProtections.getActiveSCProtectionPool(_ppID);
        require(poolAddress != address(0),"There is no SCPool for specified protocol");
        ISCPool pool = ISCPool(poolAddress);
        require(pool.poolType() == 3, "Incorrect pool type");
        return _nextClaimFillPayment(_ppID, _timestamp, pool);
    }

    function _fillClaim(ISCPool _pool, uint64 _timestamp) private {
        require(_pool.poolType() == 3, "Incorrect pool type");
        bytes32 _ppID = _pool.ppID();

        require(_timestamp < now, "Incorrect claim timestamp");
        uint64 timestamp = (_timestamp / 86400) * 86400; //(round to day)
        require(timestamp > (now - claimFillPeriod - 1 days), "Claim event date is too old");
        uint256 claimFillPayment = _nextClaimFillPayment(_ppID, _timestamp, _pool);
        ClaimStatus status = claims[_ppID][timestamp].status;

        if(status == ClaimStatus.NoClaim){
            status = ClaimStatus.New;
            claims[_ppID][timestamp] = SCProtectionClaim(_pool, new address[](0), 0, uint64(block.timestamp), status);
            scProtections.setClaimLock(address(_pool), timestamp);
        }
        require (status == ClaimStatus.New || status == ClaimStatus.InReview, "Incorrect claim status");

        claims[_ppID][timestamp].claimers.push(msg.sender);
        claims[_ppID][timestamp].claimPayments[msg.sender] = claims[_ppID][timestamp].claimPayments[msg.sender].add(claimFillPayment);
        
        IERC20Upgradeable(_pool.getBasicToken()).safeTransferFrom(msg.sender, address(this), claimFillPayment);

        emit ClaimFilled(msg.sender, _ppID, timestamp, address(_pool), claimFillPayment);
        
    }

    function _nextClaimFillPayment(bytes32 _ppID, uint64 _timestamp, ISCPool _pool) internal view returns(uint256){
        uint256 nextClaimFillPayment = uint256(claimCreateAmount).mul(_pool.getBasicTokenDecimals());
        if(claims[_ppID][_timestamp].status == ClaimStatus.Rejected) {
            nextClaimFillPayment = uint256(claimAppealAmount).mul(_pool.getBasicTokenDecimals());
        }
        else if(claims[_ppID][_timestamp].claimers.length > 0){
            //claim exist
            address lastClaimerAddress = claims[_ppID][_timestamp].claimers[claims[_ppID][_timestamp].claimers.length-1];
            uint256 lastClaimFillPayment = claims[_ppID][_timestamp].claimPayments[lastClaimerAddress];
            nextClaimFillPayment = lastClaimFillPayment.mul(uint256(duplicationMultiplier));
        }
        return nextClaimFillPayment;
    }

    /**
    * returns claim data.
    * [0] - claim status.
    * [1] - payout percent applied
    * [2] = amount of claimers that attempted to fill the claim (and paid the claim fee)
    * [3] = claim referenced pool
    * [4] = last status update timestamp
    */
    function getClaimData(bytes32 _ppID, uint64 _timestamp) public override view returns (uint8, uint8, uint256, address, uint64) {
        return (uint8(claims[_ppID][_timestamp].status), claims[_ppID][_timestamp].payAmountPercent,claims[_ppID][_timestamp].claimers.length, address(claims[_ppID][_timestamp].pool), claims[_ppID][_timestamp].lastStatusUpdateTimestamp);
    }

    /**
    * returns Claiming parameters:
    * [0] - create claim amount fee (without decimals, which are applied according to the pool basic token)
    * [1] - claim duplication fee multiplier.
    * [2] - appeal on claim amount fee (without decimals, which are applied according to the pool basic token)
    */
    function getClaimingParams() public view returns (uint64, uint64, uint64){
        return (claimCreateAmount, duplicationMultiplier, claimAppealAmount);
    }

  
}
