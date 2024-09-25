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
import "@openzeppelin/contracts/utils/Address.sol";
import "./MessageClient.sol";

interface VIBE {
    function issueVibeNFT(address account, uint amount) external;
}

interface Vortex {
    function mintPartner(uint tokens, address account) external;
}

interface CoreStake {
    function stakeFor(address account, uint stakeTermID) external payable;
}

contract VEO is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable,
    ReentrancyGuardUpgradeable, 
    UUPSUpgradeable,
    MessageClient 
{
    using AddressUpgradeable for address payable;

    uint public constant TASK_MINT_VEO = 1;
    uint public constant TASK_MINT_VUSD = 2;
    
    uint public constant USDC_DECIMALS = 10**6;
    //uint public constant USDC_DECIMALS = 10**18; // ONLY ON BSC

    uint public constant TOKEN_DECIMALS = 10**18;
    uint public constant MAX_BUNDLES = 280000;
    uint public constant BUNDLE_PRICE_USDC = 5 * USDC_DECIMALS; // $5 in USDC
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    uint public constant DISCOUNT_BLOCK_LIMIT = 5875200;

    uint public constant REFERRAL_VIBE_THRESHOLD = 250;
    uint public constant REFERRAL_FEE_BASIS_POINTS = 200;

    IERC20 public USDC;
    
    uint public bundlesSold;

    IERC20 public VTRO;
    IERC20 public VUSD;

    uint public bonusTxCount;

    mapping(address => uint) public referralAmountCounter;

    // event BridgeSend(uint toChainId, address indexed buyer, uint bundles);
    // event BridgeReceive(uint fromChainId, address indexed buyer, uint bundles);

    event BridgeOut(uint toChainId, uint indexed taskId, address indexed buyer, uint amount, uint quantity, address referrer);
    event BridgeIn(uint fromChainId, uint indexed taskId, address indexed buyer, uint amount, uint quantity, address referrer);

    event AirdropVEO(address indexed buyer, uint amount, uint bundles, address referrer);
    event AirdropVUSD(address indexed buyer, uint amount);

    function initialize() initializer public {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __MessageClient_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(UPGRADER_ROLE, msg.sender);
    }

    // Minting VEO by anyone NOT on Vitruveo
    function mintBridgeVEO(uint destChainId, address buyer, uint bundles, address referrer) external whenNotPaused onlyActiveChain(destChainId) {
        require(buyer != referrer, "Buyer cannot be same as Referrer");

        uint amount = bundles * BUNDLE_PRICE_USDC;
        require(USDC.transferFrom(msg.sender, address(this), amount), "Payment failed");
        _sendMessage(destChainId, abi.encode(TASK_MINT_VEO, buyer, amount, bundles, referrer));

        emit BridgeOut(destChainId, TASK_MINT_VEO, buyer, amount, bundles, referrer);
    }

    // Minting VUSD by anyone NOT on Vitruveo
    function mintBridgeVUSD(uint destChainId, address buyer, uint amount) external whenNotPaused onlyActiveChain(destChainId) {

        require(USDC.transferFrom(msg.sender, address(this), amount), "Payment failed");
        _sendMessage(destChainId, abi.encode(TASK_MINT_VUSD, buyer, amount, 0, address(0)));

        emit BridgeOut(destChainId, TASK_MINT_VUSD, buyer, amount, 0, address(0));
    }

    function messageProcess(uint, uint sourceChainId, address sender, address, uint, bytes calldata data) external override onlySelf(sender, sourceChainId)  {
        
        (uint taskId, address buyer, uint amount, uint quantity, address referrer) = abi.decode(data, (uint, address, uint, uint, address));
        emit BridgeIn(sourceChainId, taskId, buyer, amount, quantity, referrer);

        if (taskId == TASK_MINT_VEO) {
            _airdropVEO(buyer, amount, quantity, referrer);
        } else if (taskId == TASK_MINT_VUSD) {
            _airdropVUSD(buyer, amount);
        } 
    }

    // Minting VEO by anyone on Vitruveo
    function mintPublicVEO(uint bundles, address referrer) public {     
        require(msg.sender != referrer, "Buyer cannot be same as Referrer");
   
        bool discounted = block.number <= DISCOUNT_BLOCK_LIMIT;
        // (09:26:30 UTC is epoch change, Sept. 30th is epoch 340)
        // Subtract discount

        uint amount = bundles * BUNDLE_PRICE_USDC;
        if (discounted) {
            amount -= (amount * 20) / 100;
        }

        require(USDC.transferFrom(msg.sender, address(this), amount), "Payment failed");

        _airdropVEO(msg.sender, amount, bundles, referrer);
     }

    // Minting VUSD by anyone on Vitruveo
    function mintPublicVUSD(uint bundles, address referrer) public {        
        bool discounted = block.number <= DISCOUNT_BLOCK_LIMIT;
        // (09:26:30 UTC is epoch change, Sept. 30th is epoch 340)
        // Subtract discount

        uint amount = bundles * BUNDLE_PRICE_USDC;
        if (discounted) {
            amount -= (amount * 20) / 100;
        }

        require(USDC.transferFrom(msg.sender, address(this), amount), "Payment failed");

        _airdropVEO(msg.sender, amount, bundles, referrer);
     }
    
    // Minting by Admin on Vitruveo
    function mintAdminVEO(address buyer, uint bundles) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _airdropVEO(buyer, 0, bundles, address(0));
    }

    function _airdropVEO(address buyer, uint amount, uint bundles, address referrer) whenNotPaused nonReentrant internal {
        require(bundlesSold + bundles <= MAX_BUNDLES, "Max bundles sold");

        // VTRU Transfer 1 / bundle
        uint vtruAmount = bundles * TOKEN_DECIMALS;
        payable(buyer).sendValue(vtruAmount);

        // VTRU Stake 9 / bundle
        uint vtruStake = 9 * bundles * TOKEN_DECIMALS;
        CoreStake(0xf793A4faD64241c7273b9329FE39e433c2D45d71).stakeFor{value: vtruStake}(buyer, 6);

        // VTRO 15/bundle
        uint vtroAmount = 15 * bundles * TOKEN_DECIMALS;
        require(IERC20(0xDECAF2f187Cb837a42D26FA364349Abc3e80Aa5D).transfer(buyer, vtroAmount), "VTRO transfer failed");

        // VUSD Credit $1/bundle
        uint vusdAmount = bundles * USDC_DECIMALS;
        require(IERC20(0x1D607d8c617A09c638309bE2Ceb9b4afF42236dA).transfer(buyer, vusdAmount), "VUSD transfer failed");

        // Vortex 1/4 bundles
        if (bundles >= 4) {
            uint vortexAmount = bundles / 4;
            Vortex(0xABA06E4A2Eb17C686Fc67C81d26701D9b82e3a41).mintPartner(vortexAmount, buyer);
        }

        // VIBE 1/10 bundles
        if (bundles >= 10) {           
            uint vibeAmount = (bundles / 10);
            VIBE(0x8e7C7f0DF435Be6773641f8cf62C590d7Dde5a8a).issueVibeNFT(buyer, vibeAmount);
        }

        bundlesSold += bundles;

        emit AirdropVEO(buyer, amount, bundles, referrer);

        // Referral Fee Payment
        if ((amount > 0) && (referrer != address(0))) {
            uint referralFee = (amount * USDC_DECIMALS * REFERRAL_FEE_BASIS_POINTS) / 10000;
            if (referralFee > 0) {
                require(USDC.transfer(referrer, referralFee), "Payment failed");
            }

            referralAmountCounter[referrer] += amount;
            if (referralAmountCounter[referrer] >= REFERRAL_VIBE_THRESHOLD) {
                referralAmountCounter[referrer] -= REFERRAL_VIBE_THRESHOLD;
                VIBE(0x8e7C7f0DF435Be6773641f8cf62C590d7Dde5a8a).issueVibeNFT(referrer, 1);
            }
        }
    }

    function _airdropVUSD(address buyer, uint amount) whenNotPaused nonReentrant internal {
        uint vusdAmount = amount * USDC_DECIMALS;
        require(IERC20(0x1D607d8c617A09c638309bE2Ceb9b4afF42236dA).transfer(buyer, vusdAmount), "VUSD transfer failed");

        emit AirdropVUSD(buyer, amount);
    }


    function calculateAirdrop(uint bundles) public view returns(uint txAmount, uint payAmount, uint vtruAmount, uint vtruStake, uint vtroAmount, uint vusdAmount, uint vortexAmount, uint vibeAmount, uint vibeBonus) {

        if (bundlesSold + bundles <= MAX_BUNDLES) {

            txAmount = bundles * BUNDLE_PRICE_USDC;
            payAmount = txAmount;
            if (block.number <= DISCOUNT_BLOCK_LIMIT) {
                payAmount -= (txAmount * 20) / 100;
            }
            txAmount = txAmount / USDC_DECIMALS; // For convenience, return actual value without extraneous decimals
            payAmount = payAmount / USDC_DECIMALS; // For convenience, return actual value without extraneous decimals

            // VTRU Transfer 1 / bundle
            vtruAmount = bundles;

            // VTRU Stake 9 / bundle
            vtruStake = 9 * bundles;

            // VTRO 15/bundle
            vtroAmount = 15 * bundles;

            // VUSD Credit $1/bundle
            vusdAmount = bundles;

            // Vortex 1/4 bundles
            if (bundles >= 4) {
                vortexAmount = bundles / 4;
            }

            // VIBE 1/10 bundles
            if (bundles >= 10) {
                vibeAmount = bundles / 10;
                if (bundles >= 20) {
                    vibeBonus = bonusTxCount <= 1000 ? 5 : 0;
                }
            }
        }
    }

    function withdrawVTRU() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        (bool recovered, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(recovered, "Withdraw VTRU failed"); 
    }

    function withdrawUSDC() public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint balance = USDC.balanceOf(address(this));
        require(USDC.transfer(msg.sender, balance), "Withdraw USDC failed");
    }

    function withdrawTokens() public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        IERC20 vtro = IERC20(0xDECAF2f187Cb837a42D26FA364349Abc3e80Aa5D);
        IERC20 vusd = IERC20(0x1D607d8c617A09c638309bE2Ceb9b4afF42236dA);

        uint vtroBalance = vtro.balanceOf(address(this));
        require(vtro.transfer(msg.sender, vtroBalance), "Withdraw VTRO failed");

        uint vusdBalance = vusd.balanceOf(address(this));
        require(vusd.transfer(msg.sender, vusdBalance), "Withdraw VUSD failed");
    }

    function setUSDCContract(address contractAddress) public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        USDC = IERC20(contractAddress);
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
