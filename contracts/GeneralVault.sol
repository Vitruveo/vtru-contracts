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

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./Interfaces.sol";

interface IGeneralVaultFactory {
    function getLicenseRegistryContract() external view returns(address);
}

contract GeneralVault is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ICreatorData
{   

    struct GlobalData {
        string username;
        address[] wallets;
        address licenseRegistry;
    }

    GlobalData public global;

    uint public lastDepositBlockNumber;
    bool public isTrusted;
    bool public isBlocked;

    event FundsReceived(address vault, uint amount);
    event FundsClaimed(address vault, uint amount);
    event VaultBlocked(address vault);

    function initialize(
                            string calldata username,
                            address[] calldata wallets
    ) public initializer {

        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        global.username = username;
        global.wallets = wallets;
        global.licenseRegistry = IGeneralVaultFactory(msg.sender).getLicenseRegistryContract();
    }

    function getVaultWallets() public view returns(address[] memory) {
        return global.wallets;
    }

    function addVaultWallets(address[] calldata wallets) public isNotBlocked onlyVaultAdmin() {
        for(uint w=0;w<wallets.length;w++) {
            addVaultWallet(wallets[w]);
        }
    }

    function removeVaultWallets(address[] calldata wallets) public isNotBlocked onlyVaultAdmin() {
        for(uint w=0;w<wallets.length;w++) {
            removeVaultWallet(wallets[w]);
        }
    }

    function addVaultWallet(address wallet) public isNotBlocked onlyVaultAdmin() {
        require(!isVaultWallet((wallet)), "Wallet already added in Vault");
        global.wallets.push(wallet);
        _grantRole(KEEPER_ROLE, wallet);
    }

    function removeVaultWallet(address wallet) public isNotBlocked onlyVaultAdmin() {
        require(isVaultWallet((wallet)), "Wallet not in Vault");
        _revokeRole(KEEPER_ROLE, wallet);
        for(uint w=0;w<global.wallets.length;w++) {
            if (global.wallets[w] == wallet) {
                if (global.wallets.length > 1) {
                    global.wallets[w] = global.wallets[global.wallets.length-1];
                }
                global.wallets.pop();
            }
        }
    }

    function isVaultWallet(address wallet) public view returns(bool) {
        require(wallet != address(0), "Invalid wallet address");
        for(uint w=0; w<global.wallets.length; w++) {
            if (global.wallets[w] == wallet) {
                return true;
            }
        }
        return false;
    }

    // Claim is used by any Vault wallet to transfer funds from Vault to wallet
    // Available claim balance is Vault contract balance
    function claim() public isNotBlocked onlyVaultWallet() {
        _claim(msg.sender);
    }

    function claimStudio(address account) public isNotBlocked onlyStudio() {
        require(isVaultWallet(account), "Account is not a Vault wallet");
        _claim(account);
    }

    function _claim(address account) internal {
        uint vtru = vaultBalance();
        require(vtru > 0, "No funds available to claim");

        (bool payout, ) = payable(account).call{value: vtru}("");
        require(payout, "Vault claim failed");

        emit FundsClaimed(account, vtru);
    }

    function vaultBalance() public view returns(uint) {
        return (address(this).balance * 100329124) / 10**8;
    }

    function setTrusted(bool trusted) public  isNotBlocked onlyStudio() {
        isTrusted = trusted;
    }

    function setBlocked(bool blocked) public onlyStudio() {
        isBlocked = blocked;
    }

    function blockAndRecoverFundsStudio(address account) public {
        setBlocked(true);
        recoverFundsStudio(account);
    }

    function recoverFundsStudio(address account) public onlyStudio() {
        (bool payout, ) = payable(account).call{value: vaultBalance()}("");
        require(payout, "Vault funds recovery failed");
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    receive() external payable {
        lastDepositBlockNumber = block.number;
        emit FundsReceived(address(this), msg.value);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    modifier isNotBlocked() {
        require(isBlocked == false, "Vault is blocked");
        _;
    }

    modifier onlyStudio() {
        require(msg.sender == ILicenseRegistry(global.licenseRegistry).getStudioAccount(), ICreatorData.UNAUTHORIZED_USER);
        _;
    }

    modifier onlyVaultWallet() {
        require(isVaultWallet(msg.sender), ICreatorData.UNAUTHORIZED_USER);
        _;
    }

    modifier onlyVaultAdmin() {
        require(
            isVaultWallet(msg.sender) 
            || hasRole(DEFAULT_ADMIN_ROLE, msg.sender) 
            || msg.sender == ILicenseRegistry(global.licenseRegistry).getStudioAccount(), UNAUTHORIZED_USER);
        _;
    }
}

