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

interface ILicenseRegistry {
    function getCreatorVaultFactoryContract() external view returns(address); 
    function getAssetRegistryContract() external view returns(address); 
    function getCollectorCreditContract() external view returns(address); 
    function getUsdVtruExchangeRate() external view returns(uint);
    function getStudioAccount() external view returns(address);
    function getAsset(string calldata assetKey) external view returns(ICreatorData.AssetInfo memory);
    function getAvailableCredits(address account) external view returns(uint tokens, uint creditCents, uint creditOther);
    function registerTokens(address vault, uint256[] memory tokenIds, address owner) external; 
    function transferTokens(address vault, uint256[] memory tokenIds, address from, address to) external;     
}

interface ICreatorVault {
    function getCreatorCredits() external view returns(uint);
    function useCreatorCredits(uint) external;
    function isVaultWallet(address) external returns(bool);
    function mintLicensedAssets(ICreatorData.LicenseInstanceInfo memory licenseInstance, address licensee) external returns(uint[] memory);
}

interface ICreatorVaultFactory {
    function getLicenseRegistryContract() external view returns(address);
}

interface IVUSD {
    function redeem(address grantee, uint licenseInstanceId, address[5] memory payees, uint[5] memory cents) external;
    function getBalancesInCents(address account) external view returns(uint, uint);
    function calculateRedemptionAmounts(address account, address[5] memory payees, uint[5] memory cents) external view returns(uint totalVusd, uint grantVusd, uint nonGrantVusd, uint balanceVusd);
}

abstract contract ICreatorData {
    
    string public constant UNAUTHORIZED_USER = "Unauthorized user";
    uint public constant DECIMALS = 10 ** 18;

    bytes32 public constant STUDIO_ROLE = bytes32(uint(0x01));
    bytes32 public constant UPGRADER_ROLE = bytes32(uint(0x02));
    bytes32 public constant REEDEEMER_ROLE = bytes32(uint256(0x03));
    bytes32 public constant KEEPER_ROLE = bytes32(uint(0x04));
    bytes32 public constant LICENSOR_ROLE = bytes32(uint(0x05));

    struct AssetInfo {
        string key;
        CoreInfo core;
        CreatorInfo creator; 
        CreatorInfo[] collaborators; 
        uint[] licenses;
        Status status;
        Source originator;
        address editor;
        bool isPremium;
    }

    struct CoreInfo {
        string title;
        string description;
        string tokenUri;
        string[] mediaTypes; 
        string[] mediaItems;
        Status status;
    }

    struct CreatorInfo {
        address vault;
        uint256 split;
    }

    struct MediaInfo {
        string mediaType;
        string media;
    }

    struct LicenseInfo {
        uint256 id;
        uint256 licenseTypeId;
        uint64 editions; 
        uint64 editionCents;
        uint64 discountEditions;
        uint64 discountBasisPoints;
        uint64 discountMaxBasisPoints;
        uint64 available;
        string code;
        address[] licensees;
    }

    struct LicenseInstanceInfo {
        uint256 id;
        string assetKey;
        uint licenseId;
        uint[] tokenIds;
        uint licenseFeeCents;
        uint amountPaidCents;
        address[] licensees;
        uint64 licenseQuantity;
        uint16 platformBasisPoints;
        uint16 curatorBasisPoints;
        uint16 sellerBasisPoints;
        uint16 creatorRoyaltyBasisPoints;
    } 

    enum Status {
        DRAFT,
        PREVIEW,
        ACTIVE,
        HIDDEN,
        BLOCKED
    }

    enum Source {
        STUDIO,
        SELF,
        OTHER
    }
}

interface IMediaRegistry {
    function addMediaBatch(string calldata assetKey, string[] calldata mediaTypes, string[] calldata mediaItems) external;
}

interface IAssetRegistry {
    function isAsset(string calldata assetKey) external view returns(bool);
    function getAsset(string calldata assetKey) external view returns(ICreatorData.AssetInfo memory);
    function getAssetLicense(uint licenseId) external view returns(ICreatorData.LicenseInfo memory);
    function getAssetLicenses(string calldata assetKey) external view returns(ICreatorData.LicenseInfo[] memory); 
    function acquireLicense(uint licenseId, uint64 quantity, address licensee) external;
    function changeAssetStatus(string calldata assetKey, ICreatorData.Status status) external;
}
