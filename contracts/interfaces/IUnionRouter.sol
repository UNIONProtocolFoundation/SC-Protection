//---------------------------------------------------
// Copyright (c) 2020-2021 Union Protocol Foundation
//---------------------------------------------------

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

interface IUnionRouter{
    function collateralProtection(address token) external view returns (address, address); //returns (IOCProtections,IPool)
    function uunnToken() external view returns (address); //returns IUUNNRegistry
    function getAddress(uint16 key) external view returns (address);
    function getSCProtectionPool(bytes32 _ppID) external view returns (address);
}