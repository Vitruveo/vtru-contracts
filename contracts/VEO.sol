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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./MessageClient.sol";

contract VEO is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable,
    ReentrancyGuardUpgradeable, 
    UUPSUpgradeable,
    MessageClient 
{
    uint public constant USDC_DECIMALS = 10**6;
    uint public constant BUNDLE_PRICE_USDC = 5 * USDC_DECIMALS; // $5 in USDC
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    IERC20 public USDC;
    
    uint public bundlesSold;

    event BridgeSend(uint toChainId, address indexed buyer, uint bundles);
    event BridgeReceive(uint fromChainId, address indexed buyer, uint bundles);
    event Airdrop(address indexed buyer, uint bundles);

    function initialize() initializer public {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __MessageClient_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(UPGRADER_ROLE, msg.sender);
    }

    function mintBridge(uint destChainId, address buyer, uint bundles) external whenNotPaused onlyActiveChain(destChainId) {

        uint amount = bundles * BUNDLE_PRICE_USDC;
        require(USDC.transferFrom(msg.sender, address(this), amount), "Payment failed");
        _sendMessage(destChainId, abi.encode(buyer, bundles));

        emit BridgeSend(destChainId, buyer, bundles);
    }

    function messageProcess(uint, uint sourceChainId, address sender, address, uint, bytes calldata data) external override onlySelf(sender, sourceChainId)  {

        (address buyer, uint bundles) = abi.decode(data, (address, uint));
        emit BridgeReceive(sourceChainId, buyer, bundles);

        airdrop(buyer, bundles);
    }

    function mintPublic(uint bundles) public {        
        uint amount = bundles * BUNDLE_PRICE_USDC;

        if (block.number <= 5771520) {
            // (09:26:30 UTC is epoch change, Sept. 24th is epoch 334)
            // Subtract discount
            amount -= (amount * 20) / 100;
        }

        require(USDC.transferFrom(msg.sender, address(this), amount), "Payment failed");

        airdrop(msg.sender, bundles);
     }
    
    function mintAdmin(address buyer, uint bundles) public onlyRole(DEFAULT_ADMIN_ROLE) {
        airdrop(buyer, bundles);
    }

    function airdrop(address buyer, uint bundles) whenNotPaused nonReentrant internal {
//        require(bundlesSold + bundles <= MAX_BUNDLES, "Max bundles sold");


        emit Airdrop(buyer, bundles);
    }

    function withdrawVTRU() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        (bool recovered, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(recovered, "Withdraw VTRU failed"); 
    }

    function withdrawUSDC() public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint balance = USDC.balanceOf(address(this));
        require(USDC.transfer(msg.sender, balance), "Withdraw USDC failed");
    }

    function setUSDCAddress(address USDCContract) public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        USDC = IERC20(USDCContract);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
