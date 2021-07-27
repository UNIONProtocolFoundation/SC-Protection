//---------------------------------------------------
// Copyright (c) 2020-2021 Union Protocol Foundation
// SPDX-License-Identifier: GPL-2.0-or-later
//---------------------------------------------------


pragma solidity >=0.6.2 <0.8.0;

interface ISCPClaims{
    enum ClaimStatus { NoClaim, New, InReview, Approved, Rejected, Appeal, AppealRejected, FeesCollected }
    function fillClaim(bytes32 _ppID, uint64 _timestamp) external;
    function fillClaimForPool(address _poolAddress, uint64 _timestamp) external;
    function claimFeeRefund(bytes32 _ppID, uint64 _timestamp) external;
    function releaseLockOnExpiredClaim(bytes32 _ppID, uint64 _timestamp) external;
    function getClaimData(bytes32 _ppID, uint64 _timestamp) external view returns (uint8, uint8, uint256, address, uint64);
    function getNextClaimFillPayment(bytes32 _ppID, uint64 _timestamp) external view returns (uint256);
    function protectionPayoutPeriod() external view returns (uint64);
    function challengePeriod() external view returns (uint64);
    function claimFillPeriod() external view returns (uint64);
    function setClaimInReview(bytes32 _ppID, uint64 _timestamp) external;
    function setClaimApproved(bytes32 _ppID, uint64 _timestamp, uint8 _payoutPercentage) external;
    function setClaimRejected(bytes32 _ppID, uint64 _timestamp) external;
    function setClaimAppeal(bytes32 _ppID, uint64 _timestamp) external;
    function setClaimAppealRejected(bytes32 _ppID, uint64 _timestamp) external;
    function distributeClaimFee(bytes32 _ppID, uint64 _timestamp) external;
}