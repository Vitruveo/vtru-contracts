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

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vortex is 
    Initializable, 
    ERC721EnumerableUpgradeable, 
    AccessControlUpgradeable, 
    ReentrancyGuardUpgradeable, 
    UUPSUpgradeable 
{
    IERC20 public usdc;
    uint public constant USDC_DECIMALS = 10**6;
    uint public constant INITIAL_PRICE = 10 * USDC_DECIMALS; // $10 in USDC
    uint public constant FINAL_PRICE = 12500000; // $20 in USDC
    uint public constant MAX_TOKENS = 100000;
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    uint public constant MAX_AIRDROP_WINS = 3;

    struct Total {
        uint sales;
        uint tokensSold;
        uint revenue;
        uint[4] inventory;
        uint[4] counts; // common, rare, ultra, epic
        uint[4] revenues; // revenueCommon, revenueRare, revenueUltra, revenueEpic
    }

    Total public total;

    struct GlyphInfo {
        string name;
        string description;
        string glyph;
        uint code;
    }

    struct TokenInfo {
        uint tokenId;
        string rarity;
        string glyphName;
        uint glyphCode;
        bool vibe;
    }

    struct RarityStatistics {
        uint purchased;
        uint remaining;
        uint revenuePercentage;
    }

    struct WinnerInfo {
        uint drawing;
        Rarity rarity;
        address winner;        
        uint tokenId;
    }

    enum Rarity {Common, Rare, Ultra, Epic}
    mapping(uint => uint) public lastClaimed;

    mapping(uint => GlyphInfo) public glyphInfo;

    mapping(uint => uint) public tokenGlyph;
    mapping(uint => uint[]) public glyphToTokenIds;
    mapping(uint => uint) public tokenIndexInGlyph;

    mapping(uint => Rarity) public tokenRarity;
    mapping(Rarity => uint[]) public rarityToTokenIds;
    mapping(uint => uint) public tokenIndexInRarity;

    uint[] public glyphCodes;
    string[] public rarities;
    uint8[4] private rarityChances;
    uint8[4] private raritySwapRatios;

    /* BEGIN: Not used */
    mapping(uint => mapping(Rarity => uint)) public airdrops; // drawing => (rarity => blockNumber)
    mapping(uint => mapping(Rarity => WinnerInfo[])) public airdropResults; // drawing => (rarity => winners)
    mapping(address => uint) public airdropWinners; // winner => count

    // Used for data validation 
    mapping(uint => mapping(Rarity => uint)) private _airdrops; // drawing => (rarity => blockNumber)
    mapping(uint => mapping(Rarity => WinnerInfo[])) public _airdropResults; // drawing => (rarity => winners)
    mapping(address => uint) private _airdropWinners; // winner => WinnerInfo

    uint256 public constant INTERVAL_START = 25001;
    uint256 public constant ADJUST_INTERVAL = 100;
    uint256 public threshold; // Initial threshold for winning is 33%
    uint256 public totalVibes;
    uint256 public currentVibesInInterval; // deprecated
    uint256 public intervalStartMint;
    /* END: Not used */

    mapping(uint256 => bool) public vibeTokens;

    event VortexMinted(address indexed buyer, uint tokenId);//, string rarity, string glyph);
    event RevenueDeposited(address indexed sender, uint amount);
    event RevenueClaimed(address indexed claimer, uint tokenId, uint amount);
    event TokenSwapped(address indexed owner, uint[] burnedTokenIds, uint newTokenId, Rarity newRarity);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        // __ERC721_init("Vortex", "VTX");
        // __ERC721Enumerable_init();
        // __AccessControl_init();
        // __ReentrancyGuard_init();
        // __UUPSUpgradeable_init();

        // _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // _setupRole(UPGRADER_ROLE, msg.sender);

        // // Set rarity chances and swap ratios
        // rarityChances = [50, 30, 15, 5];
        // raritySwapRatios = [4, 16, 64, 4];

        // total = Total({
        //     sales: 0,
        //     tokensSold: 0,
        //     revenue: 1,
        //     inventory: [uint(50000), uint(30000), uint(15000), uint(5000)],
        //     counts: [uint(0), uint(0), uint(0), uint(0)],
        //     revenues: [uint(0), uint(0), uint(0), uint(0)]
        // });

        // // Initialize the Unicode code points for the glyphs
        // glyphCodes = [
        //     0x16A0, 0x16A2, 0x16A6, 0x16A8, 0x16B1, 0x16B2, 0x16B7, 0x16B9, 0x16BA, 0x16BE,
        //     0x16BF, 0x16C3, 0x16C7, 0x16C8, 0x16CB, 0x16CC, 0x16CD, 0x16CF, 0x16D6, 0x16D7,
        //     0x16DA, 0x16DD, 0x16DF, 0x16DE
        // ];

        // rarities = ["Common", "Rare", "Ultra", "Epic"];
    }

    function mintPublic(uint tokens) public nonReentrant {        
      //  require(block.number >= 3807220 || msg.sender == 0x2849Ec99Ff282Cd3452861561F7Cea4f82e446f5, "Minting not started");
        require(total.tokensSold + tokens <= MAX_TOKENS, "Max tokens sold");

        uint price = getPrice() * tokens;
        total.tokensSold += tokens;

        require(usdc.transferFrom(msg.sender, address(this), price), "Payment failed");
        total.sales += price;

        mint(tokens, msg.sender);
    }

    function mintPartner(uint tokens, address account) public nonReentrant {
        require(msg.sender == 0x1e189fC653BA6bEf980f2C8E173c2A24C24ddE2C, "Unauthorized user");
        require(tokens < 50, "Maximum exceeded");
        require(total.tokensSold + tokens <= MAX_TOKENS, "Max tokens sold");

        total.tokensSold += tokens;

        mint(tokens, account);
    }


    function mintAdmin(uint tokens, address account) public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(total.tokensSold + tokens <= MAX_TOKENS, "Max tokens sold");

        total.tokensSold += tokens;

        mint(tokens, account);
    }

    function mint(uint tokens, address account) internal {

        for(uint t=0; t<tokens; t++) {
            uint tokenId = totalSupply() + 1;

            Rarity rarity = getRandomRarity(tokenId);
            
            if (total.inventory[uint(rarity)] > 0) {
                total.inventory[uint(rarity)]--;
            }

            uint glyphCode = getRandomGlyphCode(tokenId);

            total.counts[uint(rarity)]++;

            tokenRarity[tokenId] = rarity;
            rarityToTokenIds[rarity].push(tokenId);
            tokenIndexInRarity[tokenId] = rarityToTokenIds[rarity].length - 1;

            tokenGlyph[tokenId] = glyphCode;
            glyphToTokenIds[glyphCode].push(tokenId);
            tokenIndexInGlyph[tokenId] = glyphToTokenIds[glyphCode].length - 1;

            _mint(account, tokenId);

            // if (tokens >= 2) {
            //     if (t % 2 == 0) {
            //         vibeTokens[tokenId] = true;
            //     }
            // } else {
            //     uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, tokenId))) % 100;
            //     if (randomNumber <= 33) {
            //         vibeTokens[tokenId] = true;
            //     }
            // }

            emit VortexMinted(account, tokenId);//, rarities[uint(rarity)], glyphInfo[glyphCode].glyph);
        }

    }

    function getRandomRarity(uint tokenId) internal view returns (Rarity) {

        Rarity lastRarity = Rarity.Common;

        for(uint t=0; t<10; t++) {
            uint random = uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, tokenId))) % 100;
            uint8[4] memory thresholds = getRarityThresholds();
            for (uint8 i = 0; i < thresholds.length; i++) {
                if (random < thresholds[i] && total.inventory[i] > 0) {
                    lastRarity = Rarity(i);
                    return Rarity(i);
                }
            }
        }
        return lastRarity; 
    }

    function getRarityThresholds() internal view returns (uint8[4] memory) {

        // Each item value is prior value plus new value
        if (total.tokensSold < MAX_TOKENS / 4) {
            return [50, 75, 90, 100]; // 50% Common, 25% Rare, 15% Ultra, 10% Epic
        } else if (total.tokensSold < MAX_TOKENS / 2) {
            return [60, 85, 95, 100]; // 60% Common, 25% Rare, 10% Ultra, 5% Epic
        } else if (total.tokensSold < 3 * MAX_TOKENS / 4) {
            return [70, 90, 98, 100]; // 70% Common, 20% Rare, 8% Ultra, 2% Epic
        } else {
            return [80, 95, 99, 100]; // 80% Common, 15% Rare, 4% Ultra, 1% Epic
        }
    }

    function getRandomGlyphCode(uint tokenId) internal view returns (uint) {
        uint random = uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, tokenId))) % glyphCodes.length;
        return glyphCodes[random];
    }

    function setGlyphInfo(
        string[] calldata names,
        string[] calldata descriptions,
        string[] calldata glyphs,
        uint[] calldata glyphUnicodes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            names.length == descriptions.length &&
            descriptions.length == glyphs.length &&
            glyphs.length == glyphUnicodes.length,
            "Array lengths must match"
        );

        for (uint i = 0; i < glyphUnicodes.length; i++) {
            glyphInfo[glyphUnicodes[i]] = GlyphInfo(names[i], descriptions[i], glyphs[i], glyphUnicodes[i]);
        }
    }

    // function _baseURI() internal view virtual override returns (string memory) {
    //     return "https://launch.honcho.exchange";
    // }

    function tokenURI(uint tokenId) override public view returns (string memory) {

        TokenInfo memory tokenInfo = getToken(tokenId);    
        require(tokenInfo.tokenId > 0, "Token ID does not exist");

	    string memory json = Base64Upgradeable.encode(bytes(string(abi.encodePacked('{"name": "Vortex NFT", "description": "Vortex NFT", "rarity": "', tokenInfo.rarity,'", "glyphName":"', tokenInfo.glyphName,'", "image": "https://bafybeigm6rwacsk7km6jiak34civd6cfdwdxhctz2vsfix62cn3dicznli.ipfs.nftstorage.link"}'))));
        return string(abi.encodePacked('data:application/json;base64,', json));
    }
    
    function getPrice() public pure returns (uint) {
        // uint currentPrice = INITIAL_PRICE + (total.tokensSold * 100); // increase of $0.0001 per token
        // if (currentPrice > FINAL_PRICE) {
        //     currentPrice = FINAL_PRICE;
        // }
        return FINAL_PRICE;
    }

    function getGlyph(uint code) public view returns (GlyphInfo memory) {
        return glyphInfo[code];
    }

    function getToken(uint tokenId) public view returns(TokenInfo memory) {
        return TokenInfo(tokenId, rarities[uint(tokenRarity[tokenId])], glyphInfo[tokenGlyph[tokenId]].name, glyphInfo[tokenGlyph[tokenId]].code, tokenId < INTERVAL_START ? true : vibeTokens[tokenId]);
    }

    function getTokens(uint startId, uint endId) public view returns (TokenInfo[] memory) {
        TokenInfo[] memory tokens = new TokenInfo[](endId-startId+1);
        for (uint i = startId; i <= endId; i++) {
            tokens[i-startId] = getToken(i);
        }
        return tokens;
    }

    function getTokens(address account) public view returns (TokenInfo[] memory) {
        uint balance = balanceOf(account);
        TokenInfo[] memory tokens = new TokenInfo[](balance);
        for (uint i = 0; i < balance; i++) {
            uint tokenId = tokenOfOwnerByIndex(account, i);
            tokens[i] = getToken(tokenId);
        }
        return tokens;
    }

    function getTokenIdsByRarity(Rarity rarity) public view returns (uint[] memory) {
        return rarityToTokenIds[rarity];
    }

    function getTokenOwnersByRarity(Rarity rarity) public view returns (address[] memory) {
        uint[] storage tokenIds = rarityToTokenIds[rarity];
        address[] memory owners = new address[](tokenIds.length);
        for (uint i = 0; i < tokenIds.length; i++) {
            owners[i] = ownerOf(tokenIds[i]);
        }
        return owners;
    }


    function getTokenStatistics() public view returns (uint, uint, uint, uint) {
        uint currentPrice = getPrice();
        uint remainingSupply = MAX_TOKENS - total.tokensSold;
        return (MAX_TOKENS, total.tokensSold, remainingSupply, currentPrice);
    }

    function getRarityStatistics(Rarity rarity) public view returns (RarityStatistics memory) {
        return RarityStatistics({
            purchased: total.counts[uint(rarity)],
            remaining: total.inventory[uint(rarity)] - total.counts[uint(rarity)],
            revenuePercentage: total.revenues[uint(rarity)] * 100 / total.revenue
        });
    }

    // function swapTokens(uint[] calldata tokenIds, Rarity desiredRarity) public nonReentrant {
    //     require(desiredRarity != Rarity.Common, "Cannot swap to Common rarity");

    //     Rarity currentRarity = tokenRarity[tokenIds[0]];
    //     require(currentRarity < desiredRarity, "Can only swap up in rarity");

    //     uint swapRatio = getSwapRatio(currentRarity, desiredRarity);

    //     require(tokenIds.length == swapRatio, "Incorrect number of tokens for swap");

    //     require(total.counts[uint(desiredRarity)] < MAX_TOKENS / 4, "No tokens available in desired rarity");

    //     for (uint i = 0; i < tokenIds.length; i++) {
    //         require(ownerOf(tokenIds[i]) == msg.sender, "Not the owner of token");
    //         require(tokenRarity[tokenIds[i]] == currentRarity, "All tokens must be of the same rarity");
    //         uint glyphCode = uint(keccak256(abi.encodePacked(tokenGlyph[tokenIds[i]])));
    //         removeTokenIdFromGlyph(glyphCode, tokenIds[i]);
    //         removeTokenIdFromRarity(currentRarity, tokenIds[i]);
    //         _burn(tokenIds[i]);
    //         decrementRarityCounter(currentRarity);
    //     }

    //     uint newTokenId = totalSupply() + 1;
    //     _mint(msg.sender, newTokenId);
    //     tokenRarity[newTokenId] = desiredRarity;
    //     incrementRarityCounter(desiredRarity);

    //     uint newGlyphCode = getRandomGlyphCode(newTokenId);
    //     tokenGlyph[newTokenId] = newGlyphCode;
    //     glyphToTokenIds[newGlyphCode].push(newTokenId);
    //     tokenIndexInGlyph[newTokenId] = glyphToTokenIds[newGlyphCode].length - 1;

    //     rarityToTokenIds[desiredRarity].push(newTokenId);
    //     tokenIndexInRarity[newTokenId] = rarityToTokenIds[desiredRarity].length - 1;

    //     emit TokenSwapped(msg.sender, tokenIds, newTokenId, desiredRarity);
    // }

    // function getSwapRatio(Rarity currentRarity, Rarity desiredRarity) internal view returns (uint) {
    //     if (currentRarity == Rarity.Common && desiredRarity == Rarity.Rare) {
    //         return raritySwapRatios[0]; // 4 Common to 1 Rare
    //     } else if (currentRarity == Rarity.Common && desiredRarity == Rarity.Ultra) {
    //         return raritySwapRatios[1]; // 16 Common to 1 Ultra
    //     } else if (currentRarity == Rarity.Common && desiredRarity == Rarity.Epic) {
    //         return raritySwapRatios[2]; // 64 Common to 1 Epic
    //     } else if (currentRarity == Rarity.Rare && desiredRarity == Rarity.Ultra) {
    //         return raritySwapRatios[0]; // 4 Rare to 1 Ultra
    //     } else if (currentRarity == Rarity.Rare && desiredRarity == Rarity.Epic) {
    //         return raritySwapRatios[1]; // 16 Rare to 1 Epic
    //     } else if (currentRarity == Rarity.Ultra && desiredRarity == Rarity.Epic) {
    //         return raritySwapRatios[0]; // 4 Ultra to 1 Epic
    //     } else {
    //         revert("Invalid swap rarities");
    //     }
    // }


    function incrementRarityCounter(Rarity rarity) internal {
        total.counts[uint(rarity)]++;
    }

    function decrementRarityCounter(Rarity rarity) internal {
        total.counts[uint(rarity)]--;
    }

    function removeTokenIdFromGlyph(uint glyphCode, uint tokenId) internal {
        uint index = tokenIndexInGlyph[tokenId];
        uint lastTokenId = glyphToTokenIds[glyphCode][glyphToTokenIds[glyphCode].length - 1];

        glyphToTokenIds[glyphCode][index] = lastTokenId;
        tokenIndexInGlyph[lastTokenId] = index;

        glyphToTokenIds[glyphCode].pop();
        delete tokenIndexInGlyph[tokenId];
    }

    function removeTokenIdFromRarity(Rarity rarity, uint tokenId) internal {
        uint index = tokenIndexInRarity[tokenId];
        uint lastTokenId = rarityToTokenIds[rarity][rarityToTokenIds[rarity].length - 1];

        rarityToTokenIds[rarity][index] = lastTokenId;
        tokenIndexInRarity[lastTokenId] = index;

        rarityToTokenIds[rarity].pop();
        delete tokenIndexInRarity[tokenId];
    }

    // function calculateShare(uint tokenId) public view returns (uint) {
    //     Rarity rarity = tokenRarity[tokenId];
    //     uint totalTokensInRarity = total.counts[uint(rarity)];
    //     uint rarityRevenue = total.revenues[uint(rarity)];

    //     return rarityRevenue / totalTokensInRarity;
    // }

    // function claimRevenue(uint tokenId) public nonReentrant {
    //     require(ownerOf(tokenId) == msg.sender, "You are not the owner of this token");
    //     uint share = calculateShare(tokenId);
    //     require(share > 0, "No revenue to claim");

    //     // Ensure the user cannot claim the same revenue twice
    //     require(lastClaimed[tokenId] < total.revenue, "Already claimed");

    //     lastClaimed[tokenId] = total.revenue;
    //     payable(msg.sender).transfer(share);
    //     emit RevenueClaimed(msg.sender, tokenId, share);
    // }

    receive() external payable {
        total.revenue += msg.value;
        uint share = msg.value / 4;
        total.revenues[0] += share;
        total.revenues[1] += share;
        total.revenues[2] += share;
        total.revenues[3] += share;
        emit RevenueDeposited(msg.sender, msg.value);
    }

    function withdrawVTRU() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        (bool recovered, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(recovered, "Withdraw VTRU failed"); 
    }

    function withdrawAllUSDC() public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint balance = usdc.balanceOf(address(this));
        require(usdc.transfer(msg.sender, balance), "Withdraw USDC failed");
    }

    function withdrawUSDC(uint amount) public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(usdc.balanceOf(address(this)) >= amount * USDC_DECIMALS, "Insufficient balance");
        require(usdc.transfer(msg.sender, amount * USDC_DECIMALS), "Withdraw USDC failed");
    }

    function setUSDC(address _usdc) public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        // Mainnet: 0xbCfB3FCa16b12C7756CD6C24f1cC0AC0E38569CF
        usdc = IERC20(_usdc);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721EnumerableUpgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
