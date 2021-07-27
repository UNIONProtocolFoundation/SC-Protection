//---------------------------------------------------
// Copyright (c) 2020-2021 Union Protocol Foundation
// SPDX-License-Identifier: GPL-2.0-or-later
//---------------------------------------------------


pragma solidity >=0.6.2 <0.8.0;

import "../../../union-protocol-oc-protection/contracts/interfaces/IPool.sol";

interface ISCPool is IPool{
    function ppID() external view returns (bytes32);
    function onPayoutCoverage(uint256 _id, uint256 _premiumToUnlock, uint256 _coverageToPay, address _beneficiary) external returns (bool);
    function onProtectionPremium(address buyer,  uint256[7] memory data) external; 
    function getWriterDataExtended(address _writer) external view returns (uint256, uint256, uint256);
}