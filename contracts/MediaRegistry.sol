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
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./Interfaces.sol";

contract MediaRegistry is
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ICreatorData
{  

    struct GlobalInfo {
        address assetRegistryContract;
        mapping(string => mapping(string => string)) media;
        mapping(string => string[]) mediaList;
    }

    GlobalInfo public global;

    function initialize() public initializer {

        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function version() public pure returns(string memory) {
        return "0.5.0";
    }

    function addMedia(string calldata assetKey, string calldata mediaType, string calldata mediaItem) public isEditor(assetKey) whenNotPaused {
        global.media[assetKey][mediaType] = mediaItem;
        global.mediaList[assetKey].push(mediaType);
    }

    function addMediaBatch(string calldata assetKey, string[] calldata mediaTypes, string[] calldata mediaItems) public isEditor(assetKey) whenNotPaused nonReentrant {
        require(mediaTypes.length == mediaItems.length, "Media Type and Media not same length");
        for(uint m=0; m<mediaItems.length; m++) {
            global.media[assetKey][mediaTypes[m]] = mediaItems[m];
            global.mediaList[assetKey].push(mediaTypes[m]);
        }
    }
    
    function getMedia(string calldata assetKey) public view returns(MediaInfo[] memory) {
        MediaInfo[] memory result = new MediaInfo[](global.mediaList[assetKey].length);

        for(uint m=0; m<global.mediaList[assetKey].length; m++) {
           string memory mediaType = global.mediaList[assetKey][m];
           result[m] = MediaInfo(mediaType, global.media[assetKey][mediaType]);
        }
        return(result);
    }

    function getMediaByType(string calldata assetKey, string calldata mediaType) public view returns(string memory) {
        return global.media[assetKey][mediaType];
    }

    function removeMedia(string calldata assetKey) public isEditor(assetKey) whenNotPaused {
        for(uint m=0; m<global.mediaList[assetKey].length; m++) {
            delete global.media[assetKey][global.mediaList[assetKey][m]];
        }

        delete global.mediaList[assetKey];
    }

    function removeMediaByType(string calldata assetKey, string calldata mediaType) public isEditor(assetKey) whenNotPaused {
        for(uint m=0; m<global.mediaList[assetKey].length; m++) {
            if (keccak256(bytes(global.mediaList[assetKey][m])) == keccak256(bytes(mediaType))) {
                if (global.mediaList[assetKey].length > 1) {
                    global.mediaList[assetKey][m] = global.mediaList[assetKey][global.mediaList[assetKey].length-1];
                }
                global.mediaList[assetKey].pop();
            }
        }
        delete global.media[assetKey][mediaType];
    }
    
    function setAssetRegistryContract(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid Asset Registry Contract address");
        global.assetRegistryContract = account;
    }

    function getAssetRegistryContract() public view returns(address) {
        return(global.assetRegistryContract);
    }

    modifier isEditor(string calldata assetKey) {
        require(
        global.assetRegistryContract == msg.sender
        || IAssetRegistry(global.assetRegistryContract).getAsset(assetKey).editor == msg.sender
        || hasRole(DEFAULT_ADMIN_ROLE, msg.sender) 
        , UNAUTHORIZED_USER);
        _;
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
}