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
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./UnorderedStringKeySet.sol";
import "./Interfaces.sol";

contract AssetRegistry is
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ICreatorData
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter public _licenseId;

    using UnorderedStringKeySetLib for UnorderedStringKeySetLib.Set;
    UnorderedStringKeySetLib.Set private assetList;

    struct GlobalInfo {
        uint assetsConsigned;
        uint premiumFee;
        uint creatorCreditsRequired;
        address mediaRegistryContract;
        mapping(string => AssetInfo) assets;
        mapping(uint => LicenseInfo) licenses;
    }

    GlobalInfo public global;


    event AssetConsigned(string indexed assetKey, address indexed creatorVault, uint[] licenses);
    event CollaboratorAdded(string indexed assetKey, address indexed collaboratorVault);
    event LicenseAdded(string indexed assetKey, uint licenseId, uint licenseTypeId);
    event AssetStatusChanged(string indexed assetKey, Status indexed status);
    event LicenseAcquired(address indexed licensee, uint indexed licenseId, uint64 quantity);

    function initialize() public initializer {

        // __Pausable_init();
        // __AccessControl_init();
        // __UUPSUpgradeable_init();
        // __ReentrancyGuard_init();

        // _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // _grantRole(UPGRADER_ROLE, msg.sender);

        // global.premiumFee = 10 * DECIMALS;
        // global.creatorCreditsRequired = 1;
    }

    function consign(
                            string calldata assetKey,
                            CoreInfo calldata core, 
                            CreatorInfo calldata creator,
                            CreatorInfo calldata collaborator1,
                            CreatorInfo calldata collaborator2,
                            LicenseInfo calldata license1,
                            LicenseInfo calldata license2,
                            LicenseInfo calldata license3,
                            LicenseInfo calldata license4
                    ) public payable whenNotPaused nonReentrant {

        require(core.mediaTypes.length > 0, "Media missing");
        require(isContract(creator.vault), "Vault does not exist");

        // Check if vault is in factory
        ICreatorVault(creator.vault).useCreatorCredits(global.creatorCreditsRequired);

        AssetInfo storage asset = global.assets[assetKey];
        asset.key = assetKey;
        asset.core = core;
        asset.creator = creator;
        asset.editor = msg.sender;

        IMediaRegistry(global.mediaRegistryContract).addMediaBatch(assetKey, core.mediaTypes, core.mediaItems);

        asset.originator = Source.OTHER;
        if (hasRole(STUDIO_ROLE, msg.sender)) {
            asset.originator = Source.STUDIO;
        } else if (ICreatorVault(creator.vault).isVaultWallet(msg.sender)) {
            asset.originator = Source.SELF;
        }
        require(asset.originator == Source.STUDIO || asset.originator == Source.SELF, UNAUTHORIZED_USER);


        if (msg.value == global.premiumFee) {
            asset.isPremium = true;   
        }

        addAssetCollaborator(assetKey, collaborator1);
        addAssetCollaborator(assetKey, collaborator2);

        addAssetLicense(assetKey, license1);
        addAssetLicense(assetKey, license2);
        addAssetLicense(assetKey, license3);
        addAssetLicense(assetKey, license4);

        assetList.insert(assetKey);
        global.assetsConsigned++;

        emit AssetConsigned(assetKey, asset.creator.vault, global.assets[assetKey].licenses);
    }

    function addAssetCollaborator(string calldata assetKey, CreatorInfo calldata collaborator) public onlyEditor(assetKey) whenNotPaused {
        // Don't use require because consign() does allow empty collaborator params
        if (collaborator.vault != address(0)) {
            require(isContract(collaborator.vault), "Collaborator Vault does not exist");
            global.assets[assetKey].collaborators.push(collaborator);
            emit CollaboratorAdded(assetKey, collaborator.vault);
        }
    }

    function addAssetLicense(string calldata assetKey, LicenseInfo memory license) public onlyEditor(assetKey) whenNotPaused {
        // Don't use require because consign() does allow empty licenseTypeId params
        if (license.licenseTypeId > 0) {
            _licenseId.increment();
            license.id = _licenseId.current();
            global.licenses[_licenseId.current()] = license;
            global.assets[assetKey].licenses.push(_licenseId.current());

            emit LicenseAdded(assetKey, _licenseId.current(), license.licenseTypeId);
        }
    }

    function getAssetLicense(uint licenseId) public view returns(LicenseInfo memory) {
        return (global.licenses[licenseId]);
    }

    function getAssetLicenses(string calldata assetKey) public view onlyActiveAsset(assetKey) returns(LicenseInfo[] memory licenses) {
        licenses = new LicenseInfo[](global.assets[assetKey].licenses.length);
        for(uint a=0; a<global.assets[assetKey].licenses.length; a++) {
            licenses[a] = global.licenses[global.assets[assetKey].licenses[a]];
        }
    }

    function acquireLicense(uint licenseId, uint64 quantity, address licensee) public onlyRole(LICENSOR_ROLE) whenNotPaused {
        require(global.licenses[licenseId].available >= quantity, "Insufficient license availability");
        global.licenses[licenseId].available -= quantity;
        global.licenses[licenseId].licensees.push(licensee);  

        emit LicenseAcquired(licensee, licenseId, quantity);      
    }

    function revokeLicense(uint licenseId, address licensee) public onlyRole(LICENSOR_ROLE) whenNotPaused {
        for(uint l=0;l< global.licenses[licenseId].licensees.length;l++) {
            if (global.licenses[licenseId].licensees[l] == licensee) {
                global.licenses[licenseId].licensees[l] = global.licenses[licenseId].licensees[global.licenses[licenseId].licensees.length - 1];
                global.licenses[licenseId].licensees.pop();
                global.licenses[licenseId].available++;
                break;
            }
        }
    }

    function isLicenseEditable(string calldata assetKey, uint licenseTypeId) public view returns(bool) {
        ICreatorData.LicenseInfo[] memory licenses = getAssetLicenses(assetKey);
        for(uint i=0;i<licenses.length;i++) {
            if (licenses[i].licenseTypeId == licenseTypeId) {
                return (global.licenses[licenses[i].id].licensees.length == 0);
            }
        }
        return false;
    }

    function updatedLicensePrice(string calldata assetKey, uint licenseTypeId, uint64 editionCents) public onlyEditor(assetKey) whenNotPaused {
        require(isLicenseEditable(assetKey, licenseTypeId), "License is not editable");

        ICreatorData.LicenseInfo[] memory licenses = getAssetLicenses(assetKey);
        for(uint i=0;i<licenses.length;i++) {
            if (licenses[i].licenseTypeId == licenseTypeId) {
                global.licenses[licenses[i].id].editionCents = editionCents;
                break;
            }
        }
    }

    function changeAssetStatus(string calldata assetKey, ICreatorData.Status status) public whenNotPaused {
        if (status == Status.BLOCKED || global.assets[assetKey].status == Status.BLOCKED) { // Only Studio can set or change from Blocked
            require(hasRole(STUDIO_ROLE, msg.sender) || hasRole(LICENSOR_ROLE, msg.sender), UNAUTHORIZED_USER);
        } else {
            require(hasRole(STUDIO_ROLE, msg.sender) || hasRole(LICENSOR_ROLE, msg.sender) || msg.sender == global.assets[assetKey].editor, UNAUTHORIZED_USER);
        }

        global.assets[assetKey].core.status = status;

        emit AssetStatusChanged(assetKey, status);
    }

    function upgradeAsset(string calldata assetKey) public payable  onlyActiveAsset(assetKey) whenNotPaused {
        require(!global.assets[assetKey].isPremium, "Asset is already premium");
        require(msg.value == global.premiumFee, "Insufficient funds");

        global.assets[assetKey].isPremium = true;
    }

    function changeAssetPremiumFee(uint fee) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        global.premiumFee = fee;
    }

    function changeCreatorCreditsRequired(uint credits) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        global.creatorCreditsRequired = credits;
    }

    function setMediaRegistryContract(address account) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid Media Registry Contract address");
        global.mediaRegistryContract = account;
    }

    function getMediaRegistryContract() public view returns(address) {
        return(global.mediaRegistryContract);
    }

    function changeAssetTokenUri(string calldata assetKey, string memory uri) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        global.assets[assetKey].core.tokenUri = uri;
    }

    function isContract(address account) public view returns (bool) { 
        uint size; 
        assembly { 
            size := extcodesize(account) 
        } 
        return size > 0; 
    }  

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function recoverVTRU() external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool recovered, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(recovered, "Recovery failed"); 
    }

    receive() external payable {
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    // The following functions are overrides required by Solidity.
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

    // function getAssetBatch(uint256 start, uint256 count) public view returns(AssetInfo[] memory) {
    //     AssetInfo[] memory result = new AssetInfo[](count);

    //     for(uint i=start; i<start+count; i++) {
    //        result[i - start] = getAssetAtIndex(i);
    //     }
    //     return(result);
    // }

    function getAssetCount() public view returns(uint count) {
        return assetList.count();
    }

    function isAsset(string calldata assetKey) public view returns(bool) {
        return assetList.exists(assetKey);
    }

    function getAsset(string calldata assetKey) public view returns(AssetInfo memory) {
        require(isAsset(assetKey), "Can't get an Asset that doesn't exist.");
        return(global.assets[assetKey]);
    }

    function getAssetAtIndex(uint index) public view returns(AssetInfo memory) {
        string memory assetKey = assetList.keyAtIndex(index);
        return global.assets[assetKey];
    }

    modifier onlyEditor(string calldata assetKey) {
        require(hasRole(STUDIO_ROLE, msg.sender) || msg.sender == global.assets[assetKey].editor, UNAUTHORIZED_USER);
        _;
    }

    modifier onlyActiveAsset(string calldata assetKey) {
        AssetInfo memory assetInfo = global.assets[assetKey];
        require(assetInfo.core.status == Status.ACTIVE, "Asset not active");
        _;
    }
}