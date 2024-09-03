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
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";
import "./Interfaces.sol";

contract CreatorVault is
    Initializable,
    ERC721EnumerableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ICreatorData
{   
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter public _tokenId;
    uint public constant EPOCH_BLOCKS = 17280;

    struct TokenInfo {
        string assetKey;
        uint licenseInstanceId;
    }

    struct GlobalData {
        uint creatorCredits;
        address[] wallets;
        address licenseRegistry;
    }

    GlobalData public global;

    mapping(uint => TokenInfo) private tokens; // tokenId => assetKey
    uint public lastDepositBlockNumber;
    bool public isTrusted;
    bool public isBlocked;

    event FundsReceived(address vault, uint amount);
    event FundsClaimed(address vault, uint amount);
    event VaultBlocked(address vault);

    function initialize(
                            string calldata vaultName,
                            string calldata vaultSymbol,
                            address[] calldata wallets
    ) public initializer {

        __ERC721_init(vaultName, vaultSymbol);
        __ERC721Enumerable_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        global.creatorCredits = 2;
        global.wallets = wallets;
        global.licenseRegistry = ICreatorVaultFactory(msg.sender).getLicenseRegistryContract();
    }

    function version() public pure returns(string memory) {
        return "0.5.5";
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

    function getCreatorCredits() public view isNotBlocked returns(uint) {
        return 10; //global.creatorCredits;
    }

    function useCreatorCredits(uint credits) public isNotBlocked {
        require(
            msg.sender == ILicenseRegistry(global.licenseRegistry).getAssetRegistryContract() ||
            msg.sender == ILicenseRegistry(global.licenseRegistry).getStudioAccount() ||
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorized user");
        //require(global.creatorCredits >= credits, "Insufficient Creator Credits");
        //global.creatorCredits -= credits;
    }

    function addCreatorCredits(uint credits) public isNotBlocked onlyStudio {
        global.creatorCredits += credits;
    }

    function tokenURI(uint tokenId) override public view returns (string memory){                   
        if (!isBlocked) {
            ICreatorData.AssetInfo memory assetInfo = ILicenseRegistry(global.licenseRegistry).getAsset(tokens[tokenId].assetKey);
            return assetInfo.core.tokenUri;
        } else {
            // https://nftstorage.link/ipfs/bafkreih7ytxgjaxfzwu44vu2iuff2tp7ony5wuvtstu5vc7phy7lhrbttm
            string memory json = Base64Upgradeable.encode(bytes(string(abi.encodePacked('{"name": "BLOCKED", "description": "", "image": "https://nftstorage.link/ipfs/bafkreih7ytxgjaxfzwu44vu2iuff2tp7ony5wuvtstu5vc7phy7lhrbttm"}'))));
            return string(abi.encodePacked('data:application/json;base64,', json));
        }
    }

    function mintLicensedAssets(ICreatorData.LicenseInstanceInfo memory licenseInstance, address licensee) public isNotBlocked returns(uint[] memory) {
        require(msg.sender == global.licenseRegistry, ICreatorData.UNAUTHORIZED_USER);
        
        uint[] memory tokenIds = new uint[](licenseInstance.licenseQuantity);
        for(uint q=0; q<licenseInstance.licenseQuantity; q++) {
            _tokenId.increment();
            _safeMint(licensee, _tokenId.current());
            tokens[_tokenId.current()] = TokenInfo(licenseInstance.assetKey, licenseInstance.id);     
            tokenIds[q] = _tokenId.current();   
        }
        return tokenIds;
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
        require(block.number >= fundsAvailableBlockNumber(), "Funds currently in holding period");

        uint vtru = vaultBalance();
        require(vtru > 0, "No funds available to claim");

        (bool payout, ) = payable(account).call{value: vtru}("");
        require(payout, "Vault claim failed");

        emit FundsClaimed(account, vtru);
    }

    function vaultBalance() public view returns(uint) {
        return (address(this).balance * 100109588) / 10**8;
    }

    function fundsAvailableBlockNumber() public view returns(uint) {
        // if (lastDepositBlockNumber == 0 || isTrusted) {
        return block.number - 1;
    //     } else {
    //         return lastDepositBlockNumber + (EPOCH_BLOCKS * 5);
    //     }
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

    function getTokenInfo(uint tokenId) public view returns(TokenInfo memory) {
        return tokens[tokenId];
    }

    function transferFrom(address from, address to, uint256 tokenId) public isNotBlocked  override(ERC721Upgradeable,IERC721Upgradeable) {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
        
        uint[] memory tokenIds = new uint[](1);
        tokenIds[0] = tokenId;
        ILicenseRegistry(global.licenseRegistry).transferTokens(address(this), tokenIds, from, to);
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable,IERC721Upgradeable) {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public isNotBlocked override(ERC721Upgradeable,IERC721Upgradeable) {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        uint[] memory tokenIds = new uint[](1);
        tokenIds[0] = tokenId;
        ILicenseRegistry(global.licenseRegistry).transferTokens(address(this), tokenIds, from, to);
        _safeTransfer(from, to, tokenId, data);
    }

    function burn(uint256 tokenId) public {
        require(isBlocked && ownerOf(tokenId) == msg.sender, "Owners may only burn tokens whose Vault is blocked");
        _burn(tokenId);
    }

    function currentSupply() public view returns (uint256) {
        return _tokenId.current();
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
        override(ERC721EnumerableUpgradeable, AccessControlUpgradeable)
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

