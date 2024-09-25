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
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";
import "./Interfaces.sol";

interface IwVTRU {
    function priceCurrent() external view returns(uint);
}

contract LicenseRegistry is
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ICreatorData
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter public _licenseInstanceId;
    CountersUpgradeable.Counter public _licenseTypeId;

    uint constant public FEE_BASISPOINTS_MAX = 2500;

    event LicenseIssued(string indexed assetKey, address licensee, uint indexed licenseId, uint indexed licenseInstanceId, uint256[] tokenIds);

    struct LicenseTypeInfo {
        uint256 id;
        string name;
        string info;
        bool isMintable;
        bool isElastic;
        bool isActive;
        address issuer;
    }

    struct GlobalInfo {
        uint256 usdVtruExchangeRate;  // deprecated
        address collectorCreditContract;
        address assetRegistryContract;
        address creatorVaultFactoryContract;
        address studioAccount;
        mapping(uint => LicenseTypeInfo) licenseTypes;
        mapping(uint => LicenseInstanceInfo) licenseInstances;
        mapping(address => uint[]) licenseInstancesByOwner;

        uint allowBlockNumber;
        mapping(address => bool) allowList;
    }

    GlobalInfo public global;

    struct OwnedTokenInfo {
        address vault;
        uint tokenId;
    }

    mapping(address => OwnedTokenInfo[]) mintRegistry;
    uint64 public platformFeeBasisPoints;
    address public vibeContract;
    address public vusdContract;

    function initialize() public initializer {
        // __Pausable_init();
        // __AccessControl_init();
        // __UUPSUpgradeable_init();
        // __ReentrancyGuard_init();

        // _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // _grantRole(UPGRADER_ROLE, msg.sender);

        // registerLicenseType("NFT-ART-1", "NFT", true, true);
        // registerLicenseType("STREAM-ART-1", "Stream", false, false);
        // registerLicenseType("REMIX-ART-1", "Remix", false, false);
        // registerLicenseType("PRINT-ART-1", "Print", false, false);

        // setAllowBlockNumber(block.number);
    }

    function version() public pure returns(string memory) {
        return "0.6.0";
    }

    function registerLicenseType(string memory name, string memory info, bool isMintable, bool isElastic) public onlyRole(DEFAULT_ADMIN_ROLE)  whenNotPaused {

        _licenseTypeId.increment();
        global.licenseTypes[_licenseTypeId.current()] = LicenseTypeInfo(
                                                                            _licenseTypeId.current(), 
                                                                            name, 
                                                                            info,
                                                                            isMintable, 
                                                                            isElastic,
                                                                            true,   // isActive
                                                                            msg.sender // issuer
                                                                        );
    }

    function changeLicenseType(uint licenseTypeId, string memory name, string memory info, bool active) public onlyRole(DEFAULT_ADMIN_ROLE)  whenNotPaused{

        global.licenseTypes[licenseTypeId].name = name;
        global.licenseTypes[licenseTypeId].info = info;
        global.licenseTypes[licenseTypeId].isActive = active;
    }

    function issueLicenseUsingCredits(string calldata assetKey, uint256 licenseTypeId, uint64 quantity) public whenNotPaused nonReentrant isAllowed(msg.sender) {

        address[] memory payees = new address[](3);
        uint[] memory feeBasisPoints = new uint[](3);
        _issueLicenseUsingCredits(msg.sender, assetKey, licenseTypeId, quantity, payees, feeBasisPoints);
    }

    function issueLicenseUsingCreditsStudio(address licensee, string calldata assetKey, uint256 licenseTypeId, uint64 quantity) public whenNotPaused nonReentrant {
        require(msg.sender == global.studioAccount, UNAUTHORIZED_USER);

        address[] memory payees = new address[](3);
        uint[] memory feeBasisPoints = new uint[](3);
        _issueLicenseUsingCredits(licensee, assetKey, licenseTypeId, quantity, payees, feeBasisPoints);
    }

    function issueLicenseUsingCreditsWithPayeesStudio(address licensee, string calldata assetKey, uint256 licenseTypeId, uint64 quantity, address[] memory payees, uint[] memory feeBasisPoints) public whenNotPaused nonReentrant {
        require(msg.sender == global.studioAccount, UNAUTHORIZED_USER);

        _issueLicenseUsingCredits(licensee, assetKey, licenseTypeId, quantity, payees, feeBasisPoints);
    }

    function _issueLicenseUsingCredits(address licensee, string calldata assetKey, uint256 licenseTypeId, uint64 quantity, address[] memory payees, uint[] memory feeBasisPoints) internal {
        require(vibeContract != address(0), "VIBE contract address not set");
        require(IAssetRegistry(global.assetRegistryContract).isAsset(assetKey), "Asset not found");
        ICreatorData.AssetInfo memory asset = IAssetRegistry(global.assetRegistryContract).getAsset(assetKey);
        require(payees.length == 3, "Payees array must have exactly 3 elements");
        require(payees.length == feeBasisPoints.length, "Payees and Fee Basis Points arrays must have same length");
        
        // 1) Check if asset license is available and get price
        ICreatorData.LicenseInfo memory licenseInfo = getAvailableLicense(assetKey, licenseTypeId, quantity);

        // 2) Redeem credits and send VTRU to vault
        _redeemVUSD(licensee, asset.creator.vault, licenseInfo.editionCents * quantity, payees, feeBasisPoints);

        // 3) Update the license available quantity
        IAssetRegistry(global.assetRegistryContract).acquireLicense(licenseInfo.id, quantity, licensee);

        // 4) Generate a license instance
        // 5) Mint assets
        // 6) Emit event regarding license instance
        _issueLicense(asset.creator.vault, assetKey, licenseTypeId, licenseInfo.id, quantity, licensee, licenseInfo.editionCents * quantity, feeBasisPoints[0]);

    }

    function _redeemVUSD(address licensee, address vault, uint editionCents, address[] memory payees, uint[] memory feeBasisPoints) internal {

        uint platformFeeCents = uint64((editionCents * getPlatformFeeBasisPoints())/10000);

        uint[] memory payeeFeeCents = new uint[](payees.length);
        for(uint p=0;p<payees.length;p++) {
            if (payees[p] != address(0)) {
                require(feeBasisPoints[p] <= FEE_BASISPOINTS_MAX, "Fee exceeds maximum limit");
                payeeFeeCents[p] = (editionCents * feeBasisPoints[p]) / 10000;
            }
        }

        IVUSD(vusdContract).redeem(
                                licensee, 
                                _licenseInstanceId.current(), 
                                [vault, vibeContract, payees[0], payees[1], payees[2]], 
                                [editionCents, platformFeeCents, payeeFeeCents[0], payeeFeeCents[1], payeeFeeCents[2]]
                            ); 
    }

    function _issueLicense(address vault, string calldata assetKey, uint licenseTypeId, uint licenseId, uint64 quantity, address licensee, uint editionCents, uint curatorBasisPoints) internal {
        _licenseInstanceId.increment();
        global.licenseInstancesByOwner[msg.sender].push(_licenseInstanceId.current());
        ICreatorData.LicenseInstanceInfo storage licenseInstanceInfo = global.licenseInstances[_licenseInstanceId.current()];
        licenseInstanceInfo.id = _licenseInstanceId.current();
        licenseInstanceInfo.assetKey = assetKey;
        licenseInstanceInfo.licenseId = licenseId;
        licenseInstanceInfo.licenseFeeCents = editionCents;
        licenseInstanceInfo.licenseQuantity = quantity;
        licenseInstanceInfo.licensees.push(licensee);
        licenseInstanceInfo.platformBasisPoints = uint16(getPlatformFeeBasisPoints());
        licenseInstanceInfo.curatorBasisPoints = uint16(curatorBasisPoints);
        // licenseInstanceInfo.sellerBasisPoints;
        // licenseInstanceInfo.creatorRoyaltyBasisPoints;

        if (global.licenseTypes[licenseTypeId].isMintable) {
            licenseInstanceInfo.tokenIds = ICreatorVault(vault).mintLicensedAssets(licenseInstanceInfo, licensee);
            require(licenseInstanceInfo.tokenIds.length > 0, "Asset minting failed");
            registerTokens(licensee, vault, licenseInstanceInfo.tokenIds);
        }

        emit LicenseIssued(assetKey, licensee, licenseId,  licenseInstanceInfo.id, licenseInstanceInfo.tokenIds);    

    }

    function registerTokens(address owner, address vault, uint256[] memory tokenIds) internal {
        for(uint t=0; t<tokenIds.length; t++) {
            mintRegistry[owner].push(OwnedTokenInfo(vault, tokenIds[t]));
        }
    }

    function unregisterTokens(address owner, uint256[] memory tokenIds) public {
        for(uint t=0; t<tokenIds.length; t++) {
            for(uint m=0; m<mintRegistry[owner].length; m++) {
                if (mintRegistry[owner][m].tokenId == tokenIds[t]) {
                    mintRegistry[owner][m] = mintRegistry[owner][mintRegistry[owner].length-1];
                    mintRegistry[owner].pop();
                    break;
                }            
            }
        }
    }

    function transferTokens(address vault, uint256[] memory tokenIds, address from, address to) public {
        require(msg.sender == vault, UNAUTHORIZED_USER);
        unregisterTokens(from, tokenIds);
        if (to != address(0)) {
            registerTokens(to, vault, tokenIds);
        }
    }   

    function getTokens(address owner) public view returns(OwnedTokenInfo[] memory) {
        return mintRegistry[owner];
    }

    function changeAssetStatus(string calldata assetKey, Status status) public whenNotPaused {
        return IAssetRegistry(global.assetRegistryContract).changeAssetStatus(assetKey, status);
    }

    function getAsset(string calldata assetKey) public view returns(ICreatorData.AssetInfo memory) {
        return IAssetRegistry(global.assetRegistryContract).getAsset(assetKey);
    }

    function getAssetLicense(uint licenseId) public view returns(ICreatorData.LicenseInfo memory) {
        return IAssetRegistry(global.assetRegistryContract).getAssetLicense(licenseId);
    }

    function getAssetLicenses(string calldata assetKey) public view returns(ICreatorData.LicenseInfo[] memory) {
        return IAssetRegistry(global.assetRegistryContract).getAssetLicenses(assetKey);
    }

    function getLicenseInstance(uint licenseInstanceId) public view returns(ICreatorData.LicenseInstanceInfo memory) {
        return global.licenseInstances[licenseInstanceId];
    }

    function getLicenseInstancesByOwner(address account) public view returns(ICreatorData.LicenseInstanceInfo[] memory) {

        uint[] memory ownedLicenseInstances = global.licenseInstancesByOwner[account];
        LicenseInstanceInfo[] memory licenseInstances = new LicenseInstanceInfo[](ownedLicenseInstances.length);
        for(uint i=0;i<ownedLicenseInstances.length;i++) {
            licenseInstances[i] = getLicenseInstance(ownedLicenseInstances[i]);
        }
        return licenseInstances;
    }

    function getAvailableCredits(address account) public view returns(uint tokens, uint creditCents, uint creditOther) {
        (uint grantCents, uint nonGrantCents) = IVUSD(vusdContract).getBalancesInCents(account);
        return (0, grantCents + nonGrantCents, nonGrantCents); 
    }

    function getBuyerBalancesInCents(address account) public view returns(uint, uint) {
        return IVUSD(vusdContract).getBalancesInCents(account);
    }

    function getBuyCapabilityInCents(address account, address[5] memory payees, uint[5] memory cents) public view returns(uint total, uint grant, uint nonGrant, uint balance) {
        (uint totalVusd, uint grantVusd, uint nonGrantVusd, uint balanceVusd) = IVUSD(vusdContract).calculateRedemptionAmounts(account, payees, cents);
        return (totalVusd/1e4, grantVusd/1e4, nonGrantVusd/1e4, balanceVusd/1e4);
    }

    function getAvailableLicense(string calldata assetKey, uint licenseTypeId, uint64 quantity) public view returns(LicenseInfo memory) {
        require(licenseTypeId > 0, "License Type not found");
        require(global.licenseTypes[licenseTypeId].isActive, "License Type not active");
        require(global.licenseTypes[licenseTypeId].isMintable, "Only mintable licenses currently supported");

        LicenseInfo memory license;
        ICreatorData.LicenseInfo[] memory licenses = IAssetRegistry(global.assetRegistryContract).getAssetLicenses(assetKey);
        for(uint i=0;i<licenses.length;i++) {
            if (licenses[i].licenseTypeId == licenseTypeId) {
                require(licenses[i].available >= quantity, "Insufficient editions available");
                license = licenses[i];
                break;
            }
        }
        return license;
    } 

    function setUsdVtruExchangeRate(uint256 centsPerVtru) public onlyRole(DEFAULT_ADMIN_ROLE) {
        global.usdVtruExchangeRate = centsPerVtru;
    }

    function getUsdVtruExchangeRate() public view returns(uint) {
        if (global.usdVtruExchangeRate > 0) {
            return(global.usdVtruExchangeRate);  // Testnet
        } else {
            uint price = IwVTRU(0x3ccc3F22462cAe34766820894D04a40381201ef9).priceCurrent();
            return(price);
        }
    }

    function setAssetRegistryContract(address account) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid Asset Registry Contract address");
        global.assetRegistryContract = account;
    }

    function getAssetRegistryContract() public view returns(address) {
        return(global.assetRegistryContract);
    }

    function setCreatorVaultFactoryContract(address account) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid Creator Vault Factory Contract address");
        global.creatorVaultFactoryContract = account;
    }

    function getCreatorVaultFactoryContract() public view returns(address) {
        return(global.creatorVaultFactoryContract);
    }

    // Studio account is required for Creator Vault
    function setStudioAccount(address account) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid Studio account address");
        global.studioAccount = account;
    }

    function getStudioAccount() public view returns(address) {
        return(global.studioAccount);
    
    }

    function addToAllowList(address allow) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        global.allowList[allow] = true;
    }

    function removeFromAllowList(address allow) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        delete global.allowList[allow];
    }

    function setPlatformFeeBasisPoints(uint64 basisPoints) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        platformFeeBasisPoints = basisPoints;
    }

    function getPlatformFeeBasisPoints() public view returns(uint64) {
        return(platformFeeBasisPoints);
    }

    function setVIBEContract(address account) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid address");
        vibeContract = account;
    }

    function setVUSDContract(address account) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid address");
        vusdContract = account;
    }

    function getVIBEContract() public view returns(address) {
        return(vibeContract);
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    modifier isAllowed(address licensee) {
        require(global.allowList[licensee] == true, "Licensing not permitted");
        _;
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
}