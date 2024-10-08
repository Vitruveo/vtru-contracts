/*
 *
 *
 *   ██╗   ██╗    ██╗    ████████╗    ██████╗     ██╗   ██╗    ██╗   ██╗    ███████╗     ██████╗ 
 *   ██║   ██║    ██║    ╚══██╔══╝    ██╔══██╗    ██║   ██║    ██║   ██║    ██╔════╝    ██╔═══██╗
 *   ██║   ██║    ██║       ██║       ██████╔╝    ██║   ██║    ██║   ██║    █████╗      ██║   ██║
 *   ╚██╗ ██╔╝    ██║       ██║       ██╔══██╗    ██║   ██║    ╚██╗ ██╔╝    ██╔══╝      ██║   ██║
 *    ╚████╔╝     ██║       ██║       ██║  ██║    ╚██████╔╝     ╚████╔╝     ███████╗    ╚██████╔╝
 *     ╚═══╝      ╚═╝       ╚═╝       ╚═╝  ╚═╝     ╚═════╝       ╚═══╝      ╚══════╝     ╚═════╝ 
 * 
 */

// SPDX-License-Identifier: MIT
// Author: Nik Kalyani @techbubble

pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./GeneralVaultBeacon.sol";
import "./GeneralVault.sol";
import "./UnorderedStringKeySet.sol";

contract GeneralVaultFactory is Ownable {
    using UnorderedStringKeySetLib for UnorderedStringKeySetLib.Set;
    UnorderedStringKeySetLib.Set private vaultList;

    address public licenseRegistryContract;
    mapping(string => address) private vaultsByKey;
    mapping(string => address) private vaultsByUsername;
    GeneralVaultBeacon immutable beacon;

    event VaultCreated(string indexed vaultKey, string indexed username, address indexed vault);

    constructor(address initTarget, address licenseRegistry) {
        beacon = new GeneralVaultBeacon(initTarget);
        licenseRegistryContract = licenseRegistry;
    }

    function createVault(string calldata vaultKey, string calldata username, address[] memory wallets) public {
        require(licenseRegistryContract != address(0), "License Registry contract address not set");
        require(vaultsByKey[vaultKey] == address(0), "Vault already exists");

        BeaconProxy vault = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(GeneralVault(payable(address(0))).initialize.selector, username, wallets)
        );
        vaultsByKey[vaultKey] = address(vault);
        vaultsByUsername[username] = address(vault);
        vaultList.insert(vaultKey);

        emit VaultCreated(vaultKey, username, address(vault));
    }

    function setLicenseRegistryContract(address account) public onlyOwner {
        require(account != address(0), "Invalid License Registry Contract address");
        licenseRegistryContract = account;
    }

    function getLicenseRegistryContract() public view returns(address) {
        return(licenseRegistryContract);
    }

    function getBeacon() public view returns (address) {
        return address(beacon);
    }

    function getImplementation() public view returns (address) {
        return beacon.implementation();
    }

    function getVaultBatch(uint256 start, uint256 count) public view returns(address[] memory) {
        address[] memory result = new address[](count);

        for(uint i=start; i<start+count; i++) {
           result[i - start] = getVaultAtIndex(i);
        }
        return(result);
    }

    function getVaultCount() public view returns(uint count) {
        return vaultList.count();
    }

    function isVault(string memory vaultKey) public view returns(bool) {
        return vaultList.exists(vaultKey);
    }

    function getVaultByKey(string memory vaultKey) public view returns(address) {
        require(vaultList.exists(vaultKey), "Can't get a Vault that doesn't exist.");
        return(vaultsByKey[vaultKey]);
    }

    function getVaultByUsername(string memory username) public view returns(address) {
        return(vaultsByUsername[username]);
    }

    function getVaultAtIndex(uint index) public view returns(address) {
        string memory vaultKey = vaultList.keyAtIndex(index);
        return vaultsByKey[vaultKey];
    }
    
    function getKeyAtIndex(uint index) public view returns(string memory) {
        return vaultList.keyAtIndex(index);
    }
}