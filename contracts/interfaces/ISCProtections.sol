//---------------------------------------------------
// Copyright (c) 2020-2021 Union Protocol Foundation
// SPDX-License-Identifier: GPL-2.0-or-later
//---------------------------------------------------


pragma solidity >=0.6.2 <0.8.0;

interface ISCProtections{
    function create(uint256[9] memory data, bytes memory signature, uint256 deadline) external returns (address);
    function createTo(uint256[9] memory data, bytes memory signature, address erc721Receiver, uint256 deadline) external returns (address);
    function version() external pure returns (uint32);
    function getProtectionData(uint256 id) external view returns (address, bytes32, uint256, uint256, uint, uint);
    function withdrawPremium(uint256 _id, uint256 _premium) external;
    function getActiveSCProtectionPool(bytes32 _ppID) external view returns (address);
    function isClaimLocked(address _pool) external view returns (bool);
    function setClaimLock(address _pool, uint64 _timestamp) external; 
    function releaseClaimLock(address _pool, uint64 _timestamp) external;
}