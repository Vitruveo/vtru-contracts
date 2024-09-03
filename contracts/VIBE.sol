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
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

interface IPool {
   function depositRevenue(uint256 poolId) external payable;
}

contract VIBE is
    Initializable,
    ERC721EnumerableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{

    struct VibeNFT {
        uint tokenId;
        uint denomination;
        uint claimed;
    }

    struct GlobalData {
        mapping(uint => VibeNFT) nfts;
        mapping(uint => uint) denominationCounts;
        uint nextTokenId;
        uint issuedShares;
        uint totalRevenueShare;
        uint claimedRevenueShare;
    }

    address public poolContract;
    uint public totalPoolRevenue;

    uint public constant MAX_TOTAL_SHARES = 1000000;
    uint public constant GENERAL_POOL_SHARES = 40000;
    uint public constant VALIDATOR_POOL_SHARES = 138465;
    uint public constant DEX_POOL_SHARES = 10000;
    uint public constant CREATOR_POOL_SHARES = 10000;
    uint public constant BUYER_POOL_SHARES = 10000;
    uint public constant TOTAL_POOL_SHARES = GENERAL_POOL_SHARES + VALIDATOR_POOL_SHARES + DEX_POOL_SHARES + CREATOR_POOL_SHARES + BUYER_POOL_SHARES;

    /****************************************************************************/
    /*                                  ROLES                                   */
    /****************************************************************************/
    bytes32 public constant UPGRADER_ROLE = bytes32(uint(0x01));
    bytes32 public constant GRANTER_ROLE = bytes32(uint(0x02));

    uint[] public DENOMINATIONS;
    GlobalData public global;
    uint public stakeQuota;

    event VibeNFTGranted(uint indexed tokenId, uint indexed denomination, address indexed account);
    event VibeNFTFundsClaimed(uint indexed tokenId, address indexed account, uint claimed);
    event VibePoolRevenueDeposited(uint indexed poolId, uint256 amount);

     function initialize() public initializer {
        __ERC721_init("Vitruveo Income Building Engine", "VIBE");
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(GRANTER_ROLE, msg.sender);

        DENOMINATIONS = [ 1000, 100, 50, 20, 10, 5, 1 ];

        global.nextTokenId = 1;
        global.issuedShares = 0;
        global.totalRevenueShare = 0;
        global.claimedRevenueShare = 0;
    }

    function calcDenominations(uint amount) public view returns (uint[] memory) {
        uint remainingValue = amount;
        uint[] memory denomCounts = new uint[](DENOMINATIONS.length);

        for (uint i = 0; i<DENOMINATIONS.length; i++) {
            uint count = remainingValue / DENOMINATIONS[i];
            denomCounts[i] = count;
            remainingValue -= count * DENOMINATIONS[i];
        }

        return denomCounts;
    }

    function issueVibeNFTBatch(address[] memory accounts, uint[] memory amounts) public onlyRole(GRANTER_ROLE) whenNotPaused {
        require(accounts.length == amounts.length, "Account and Amount lengths don't match");

        for(uint i=0; i<accounts.length; i++) {
            issueVibeNFT(accounts[i], amounts[i]);
        }
    }

    function setStakeQuota(uint quota) public onlyRole(DEFAULT_ADMIN_ROLE) {
        stakeQuota = quota;
    }

    function issueVibeNFTForStake(address account, uint amount) public onlyRole(GRANTER_ROLE) whenNotPaused { 
        require(stakeQuota >= amount, "Stake quota not available");
        stakeQuota -= amount;
        issueVibeNFT(account, amount);
    }

    function issueVibeNFTDenoms(address account, uint[] memory denomCounts) public onlyRole(GRANTER_ROLE) whenNotPaused {
        uint amount = 0;
        for(uint d=0; d<denomCounts.length;d++) {
            amount += DENOMINATIONS[d] * denomCounts[d];
        }

        require(global.issuedShares + TOTAL_POOL_SHARES + amount <= MAX_TOTAL_SHARES, "Total denomination and pool value cannot exceed 1 million");

        for (uint i=0; i<DENOMINATIONS.length; i++) {
            for (uint j = 0; j < denomCounts[i]; j++) {
                global.nfts[global.nextTokenId] = VibeNFT(global.nextTokenId, DENOMINATIONS[i], 0);

                _mint(account, global.nextTokenId);
                emit VibeNFTGranted(global.nextTokenId, DENOMINATIONS[i], account);

                global.issuedShares += DENOMINATIONS[i];
                global.denominationCounts[DENOMINATIONS[i]]++;
                global.nextTokenId++;
            }
        }
    }

    function issueVibeNFT(address account, uint amount) public onlyRole(GRANTER_ROLE) whenNotPaused {
        uint[] memory denomCounts = calcDenominations(amount);
        issueVibeNFTDenoms(account, denomCounts);
    }

    function revokeVibeNFT(uint tokenId) public onlyRole(GRANTER_ROLE) whenNotPaused {
        global.issuedShares -= global.nfts[tokenId].denomination;
        global.denominationCounts[global.nfts[tokenId].denomination]--;
        delete global.nfts[tokenId];
        _burn(tokenId);
    }

    function getVibeNFT(uint tokenId) public view returns (address, VibeNFT memory) {
        address owner = ownerOf(tokenId);
        return (owner, global.nfts[tokenId]);
    }
    
    function getVibeNFTBatch(uint startTokenId, uint endTokenId) public view returns (address[] memory, VibeNFT[] memory) {
        uint size = endTokenId - startTokenId + 1;
        VibeNFT[] memory tokens = new VibeNFT[](size);
        address[] memory owners = new address[](size);

        for(uint i=0; i<size; i++) {
            tokens[i] = global.nfts[startTokenId + i];
            owners[i] = ownerOf(startTokenId + i);
        }

        return (owners, tokens);
    }

    function getVibeNFTsByOwner() public view returns (VibeNFT[] memory) {
        return getVibeNFTsByOwner(msg.sender);
    }

    function getVibeNFTsByOwner(address account) public view returns (VibeNFT[] memory) {
        uint balance = balanceOf(account);        
        VibeNFT[] memory tokens = new VibeNFT[](balance);
        for(uint i=0;i<balance;i++) {
            uint tokenId = tokenOfOwnerByIndex(account, i);
            tokens[i] = global.nfts[tokenId];
        }
        return tokens;
    }

    function getRevenueShareByOwner() public view returns(uint, uint) {
         return getRevenueShareByOwner(msg.sender);
    }

    function getRevenueShareByOwner(address account) public view returns(uint, uint) {
        uint balance = balanceOf(account);        
        uint totalUnclaimedRevenueShare = 0;
        uint totalClaimedRevenueShare = 0;
        for(uint i=0;i<balance;i++) {
            uint tokenId = tokenOfOwnerByIndex(account, i);
            uint unclaimedRevenueShare = calcUnclaimedRevenueShare(tokenId);
            totalClaimedRevenueShare += global.nfts[tokenId].claimed;
            if (ownerOf(tokenId) == account && unclaimedRevenueShare > 0) {
                totalUnclaimedRevenueShare += unclaimedRevenueShare;
            }
        }

        return (totalClaimedRevenueShare, totalUnclaimedRevenueShare);
    }


    function calcUnclaimedRevenueShare(uint tokenId) public view returns (uint) {
        VibeNFT memory token = global.nfts[tokenId];
        uint totalClaimable = (token.denomination * global.totalRevenueShare) / MAX_TOTAL_SHARES;
        return totalClaimable - token.claimed;
    }

    function claimRevenueShareByToken(uint tokenId) public whenNotPaused {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this token");
        uint unclaimedRevenueShare = calcUnclaimedRevenueShare(tokenId);
        require(unclaimedRevenueShare > 0, "No unclaimed revenue share");

        global.nfts[tokenId].claimed += unclaimedRevenueShare;
        global.claimedRevenueShare += unclaimedRevenueShare;

        (bool claim, ) = payable(msg.sender).call{value: unclaimedRevenueShare}("");
        require(claim, "Failed to claim due to insufficient funds");        

        emit VibeNFTFundsClaimed(global.nextTokenId, msg.sender, unclaimedRevenueShare);
    }

    function claimRevenueShareByOwner() public whenNotPaused {
        uint balance = balanceOf(msg.sender);        
        uint totalUnclaimedRevenueShare = 0;
        for(uint i=0;i<balance;i++) {
            uint tokenId = tokenOfOwnerByIndex(msg.sender, i);
            uint unclaimedRevenueShare = calcUnclaimedRevenueShare(tokenId);
            if (ownerOf(tokenId) == msg.sender && unclaimedRevenueShare > 0) {
                totalUnclaimedRevenueShare += unclaimedRevenueShare;
                global.nfts[tokenId].claimed += unclaimedRevenueShare;
                global.claimedRevenueShare += unclaimedRevenueShare;
                emit VibeNFTFundsClaimed(tokenId, msg.sender, unclaimedRevenueShare);
            }
        }

       require(totalUnclaimedRevenueShare > 0, "No unclaimed revenue share");

       (bool claim, ) = payable(msg.sender).call{value: totalUnclaimedRevenueShare}("");
       require(claim, "Failed to claim due to insufficient funds");        

    }

    function depositPoolRevenue(uint revenue) internal returns(uint balanceRevenue) {
        require(poolContract != address(0), "Invalid Pool contract address");

        uint general = (GENERAL_POOL_SHARES * revenue) / MAX_TOTAL_SHARES;
        IPool(poolContract).depositRevenue{value: general}(0);

        uint validator = (VALIDATOR_POOL_SHARES * revenue) / MAX_TOTAL_SHARES;
        IPool(poolContract).depositRevenue{value: validator}(1);

        uint dex = (DEX_POOL_SHARES * revenue) / MAX_TOTAL_SHARES;
        IPool(poolContract).depositRevenue{value: dex}(2);

        uint creator = (CREATOR_POOL_SHARES * revenue) / MAX_TOTAL_SHARES;
        IPool(poolContract).depositRevenue{value: creator}(3);

        uint buyer = (BUYER_POOL_SHARES * revenue) / MAX_TOTAL_SHARES;
        IPool(poolContract).depositRevenue{value: buyer}(4);

        uint poolRevenue = general + validator + dex + creator + buyer;
        balanceRevenue = revenue - poolRevenue;

        totalPoolRevenue += poolRevenue;
    }

    receive() external payable {

        uint balanceRevenue = depositPoolRevenue(msg.value);
        global.totalRevenueShare += balanceRevenue;
    }

    function adminTransferVibeNFT(uint256 tokenId, address to) public onlyRole(GRANTER_ROLE) {
        _transfer(ownerOf(tokenId), to, tokenId);
    }

    function setPoolContract(address contractAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(poolContract != address(0), "Invalid Pool contract address");

        poolContract = contractAddress;
    }

    function tokenURI(uint tokenId) override public view returns (string memory){

        VibeNFT memory vibeNFT = global.nfts[tokenId];    
	    string memory json = Base64Upgradeable.encode(bytes(string(abi.encodePacked('{"name": "VIBE (', StringsUpgradeable.toString(vibeNFT.denomination), ')", "description": "Vitruveo Vibe NFT", "image": "https://vitruveo-protocol.s3.amazonaws.com/VIBE/', StringsUpgradeable.toString(vibeNFT.denomination), '.png"}'))));
	
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function stats() public view returns (
        uint,
        uint,
        uint[] memory,
        uint[] memory,
        uint,
        uint
    ) {

        uint[] memory denominationCounts = new uint[](DENOMINATIONS.length);
        for(uint i=0;i<DENOMINATIONS.length;i++) {
            denominationCounts[i] = global.denominationCounts[DENOMINATIONS[i]];
        }

        return (
            global.nextTokenId - 1,
            global.issuedShares + TOTAL_POOL_SHARES,
            DENOMINATIONS,
            denominationCounts,
            global.totalRevenueShare,
            global.claimedRevenueShare
        );
    }

    function version() public pure returns(string memory) {
        return "0.6.0";
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function recoverVTRU() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(payable(msg.sender).send(address(this).balance));
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

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

    // function split(uint tokenId, uint[] memory splitDenominations) public {
    //     require(ownerOf(tokenId) == msg.sender, "Not the owner of this token");
    //     VibeNFT memory token = global.nfts[tokenId];

    //     uint totalSplitValue = 0;
    //     for (uint i = 0; i < splitDenominations.length; i++) {
    //         totalSplitValue += splitDenominations[i];
    //     }
    //     require(totalSplitValue == token.denomination, "Split denominations must add up to the original denomination value");

    //     uint totalClaimed = token.claimed;
    //     global.issuedShares -= token.denomination;
    //     global.denominationCounts[token.denomination]--;
    //     delete global.nfts[tokenId];
    //     burn(tokenId);

    //     for (uint i = 0; i < splitDenominations.length; i++) {
    //         uint newClaimed = (splitDenominations[i] * totalClaimed) / totalSplitValue;
    //         global.nfts[global.nextTokenId] = VibeNFT(global.nextTokenId, splitDenominations[i], newClaimed);
    //         mint(msg.sender, global.nextTokenId);
    //         global.issuedShares += splitDenominations[i];
    //         global.denominationCounts[splitDenominations[i]]++;
    //         global.nextTokenId++;
    //     }
    // }

    // function merge(uint[] memory tokenIds) public {
    //     uint totalMergeValue = 0;
    //     uint totalClaimed = 0;

    //     for (uint i = 0; i < tokenIds.length; i++) {
    //         require(global.tokenOwners[tokenIds[i]] == msg.sender, "Not the owner of this token");
    //         totalMergeValue += global.nfts[tokenIds[i]].denomination;
    //         totalClaimed += global.nfts[tokenIds[i]].claimed;
    //     }

    //     require(global.issuedShares - totalMergeValue + totalMergeValue <= MAX_TOTAL_SHARES, "Total denomination value cannot exceed 1 million");

    //     for (uint i = 0; i < tokenIds.length; i++) {
    //         global.issuedShares -= global.nfts[tokenIds[i]].denomination;
    //         global.denominationCounts[global.nfts[tokenIds[i]].denomination]--;
    //         delete global.nfts[tokenIds[i]];
    //     }

    //     global.nfts[global.nextTokenId] = VibeNFT(global.nextTokenId, totalMergeValue, totalClaimed);
    //     global.tokenOwners[global.nextTokenId] = msg.sender;
    //     global.issuedShares += totalMergeValue;
    //     global.denominationCounts[totalMergeValue]++;
    //     global.nextTokenId++;
    // }

}

