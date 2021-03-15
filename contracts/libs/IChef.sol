// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IChef {
    function cake() external view returns (address);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function lockedSupply() external view returns(uint256);
}