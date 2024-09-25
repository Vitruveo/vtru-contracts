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
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Base64Upgradeable.sol";

interface VitruveoBoosterNFT {

    struct boosterInfo {
        uint256 tokenId;
        bool    isBoosted;
        uint256 tokensDue;
        string  boosterName;
        uint256 boosterType;
        uint256 basisPoints;
        uint256 lockedBlocks;
        uint256 vestingBlocks;
        uint256 txBlockNumber;
        string  boosterStatus;
        string  txHashForPayment;
        uint256 chainIdForPayment;
    }

    function ownerOf(uint256 tokenId) external view returns(address);
    function getBoosterInfo(uint256 tokenId) external view returns (boosterInfo memory);
    function consumeBoost(uint256 tokenId) external;
}

interface VIBE {
    function issueVibeNFTForStake(address account, uint amount) external;
}

interface CoreStake {
    function unstakeRedeem(address account, uint amount) external;
    function unstakeRedeemPreview(address account, uint amount) external view returns(uint earlyUnstaked, uint earlyReward, bool allowRedeem);
}

contract CoreVestV2 is
    Initializable,
    ERC721Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    
    /****************************************************************************/
    /*                                  COUNTERS                                */
    /****************************************************************************/
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _coreClassId;
    CountersUpgradeable.Counter private _tokenId;

    uint public constant SCALER = 10 ** 10;
    uint public constant DECIMALS = 10 ** 18;

    /****************************************************************************/
    /*                                  ROLES                                   */
    /****************************************************************************/
    bytes32 public constant GRANTER_ROLE = bytes32(uint256(0x01));
    bytes32 public constant BOOSTER_ROLE = bytes32(uint256(0x02));
    bytes32 public constant UPGRADER_ROLE = bytes32(uint256(0x03));

    /****************************************************************************/
    /*                                 TOKENS                                   */
    /****************************************************************************/

    struct CoreNFTClass {
        uint256 id;
        string  name; 
        bool    isTransferable;
        bool    allowMultiple; 
        bool    isActive;
        uint256 totalGrants;
    }

    struct CoreNFT {
        uint256 id;
        uint256 classId;            // Class of CoreNFT
        uint256 grantBlock;         // Block number of grant, 0 = current

        uint256 grantAmount;        // Total grant amount
        uint256 depositAmount;      // Amount being deposited (could be less or more than grant)

        uint16 unlockBasisPoints;   // Unlocked grant amount percentage
        uint16 voteCredits;         // Number of Vote Credits

        uint16 lockMonths;          // Lock period in months
        uint16 vestingMonths;       // Vesting period in months

        uint256 claimedGrantAmount; // Grant amount already claimed
        uint256 claimedRebaseAmount;// Rebase amount already claimed

        uint16 boosts;              // Number of boosts received
        uint16 boostBasisPoints;    // Boost percentage added

        bool isRevocable;           // NFT can be revoked
        bool isRevoked;             // NFT has been revoked

        bool isKyc;
    }

    struct GlobalData {
        string classImageURI;
        uint256 totalDepositBalance;        // Amount deposited at time of grant; used to calculate rebase pro rata share
        uint256 boosts;
        
        mapping(uint256 => CoreNFT) CoreNFTs;
        mapping(uint256 => CoreNFTClass) CoreNFTClasses;
        mapping(address => uint256[]) CoreNFTsByOwner;
        mapping(uint256 => uint256) TotalNFTsByClass;
    }


    struct CalcData {
        uint256 unlockAmountDue;
        uint256 adjustedGrantAmount;
        uint256 vestedAmountDue;
        uint256 grantClaimAmount;
        uint256 rebaseDifference;
        uint256 rebaseShare;
        uint256 totalAmountDue;
        uint256 rebaseClaimAmount;
        uint256 months;
        uint256 rebaseMultiplier;
        uint256 rebasedAmountDue;
    }

    
    GlobalData public global;

    uint public BLOCKS_IN_MONTH;

    uint256 public totalCurrentDepositBalance;     // Amount remaining in contract after claims
    VitruveoBoosterNFT boosterContract;

    uint256 public constant BOOSTER_ESCROW = 1090000 * DECIMALS;

    event CoreNFTGranted(uint256 indexed tokenId, uint256 indexed classId, address indexed account, uint256 refunded);
    event CoreNFTRevoked(uint256 indexed tokenId);
    event CoreNFTFundsClaimed(uint256 indexed tokenId, uint256 claimAmount, uint256 rebaseClaimAmount, uint256 claimTotal);

    function initialize() public initializer {
        __ERC721_init("Vitruveo Core NFT 2", "VCORE");
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GRANTER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        BLOCKS_IN_MONTH = 17280 * 30; // Configurable for testing
        initClasses();
    }

    function initClasses() internal {
        global.classImageURI = "https://nftstorage.link/ipfs/bafybeic4nf6zt6vktz5hspeqw5r7hpz7bt5r4uke6kmwobfoug2fcoh2y4/";
        // if (!global.CoreNFTClasses[1].isActive) {
        //     registerCoreClass(1, "Nexus", true, false);
        //     registerCoreClass(2, "Maxim", true, false);
        //     registerCoreClass(3, "Validator", false, false);
        //     registerCoreClass(4, "Steward", false, false);
        //     registerCoreClass(5, "Dreamer", true, true);
        //     registerCoreClass(6, "Benefactor", true, true);
        //     registerCoreClass(7, "Trooper", false, true);
        // }
    }


    function grantCoreNFT(
        uint256 classId,
        address account,
        uint256 grantBlock,
        uint256 grantAmount,
        uint16 unlockBasisPoints,
        uint16 lockMonths,
        uint16 vestingMonths,
        uint256 claimedGrantAmount,
        uint16 voteCredits,
        bool isRevocable
    ) public payable onlyRole(GRANTER_ROLE) whenNotPaused {

        grantCoreNFT(classId, account, grantBlock, grantAmount, unlockBasisPoints, lockMonths, vestingMonths, claimedGrantAmount, voteCredits, isRevocable, false);
    }

    function grantCoreNFT(
        uint256 classId,
        address account,
        uint256 grantBlock,
        uint256 grantAmount,
        uint16 unlockBasisPoints,
        uint16 lockMonths,
        uint16 vestingMonths,
        uint256 claimedGrantAmount,
        uint16 voteCredits,
        bool isRevocable,
        bool isKyc
    ) public payable onlyRole(GRANTER_ROLE) whenNotPaused {

        require(
            unlockBasisPoints < 10000,   
            "Unlock basis points must be less than 10000"
        );

        require(
            grantAmount > claimedGrantAmount,
            "Grant amount must be larger than claimed grant amount" 
        );

        require(
            vestingMonths > 0,
            "Vesting duration must be greater than zero"
        );

        require(
            lockMonths <= vestingMonths,
            "Lock duration cannot exceed vesting duration"
        );

        CoreNFTClass memory coreNFTClass = global.CoreNFTClasses[classId];
        // Check if the class being granted is active
        require(
            coreNFTClass.isActive == true, 
            "Specified token class not active."
        );

        // Check if the class being granted is not already owned or allows multiple
        require(
            isGrantAllowed(account, classId),
            "Specified class may not be granted to this account"
        );

        _tokenId.increment();

        CoreNFT storage newCoreNFT = global.CoreNFTs[_tokenId.current()];
        newCoreNFT.id = _tokenId.current();
        newCoreNFT.classId = classId;
        newCoreNFT.grantBlock = grantBlock == 0 ? block.number : grantBlock;

        newCoreNFT.lockMonths = lockMonths;
        newCoreNFT.vestingMonths = vestingMonths;
        newCoreNFT.voteCredits = voteCredits;
        newCoreNFT.isRevocable = isRevocable;
        newCoreNFT.isKyc = isKyc;

        newCoreNFT.grantAmount = grantAmount;
        newCoreNFT.depositAmount = grantAmount - claimedGrantAmount;

        // Grant request must include coins granted (less already paid)
        require(
            msg.value >= newCoreNFT.depositAmount, 
            "Insufficient funds for grant amount"
        );

        newCoreNFT.claimedGrantAmount = claimedGrantAmount; // important this is set here for calculate call
        newCoreNFT.claimedRebaseAmount = 0;
        newCoreNFT.unlockBasisPoints = unlockBasisPoints;

        global.CoreNFTsByOwner[account].push(newCoreNFT.id); // Fixed bug
        global.TotalNFTsByClass[classId]++;

        _mint(account, newCoreNFT.id);

        _processGrantClaim(newCoreNFT, account);

        if (msg.value > newCoreNFT.depositAmount) {
            // return excess amount
           (bool refunded, ) = payable(msg.sender).call{value: msg.value - newCoreNFT.depositAmount}("");
           require(refunded, "Failed to refund");        
        }

        emit CoreNFTGranted(newCoreNFT.id, classId, account, msg.value - newCoreNFT.depositAmount);
    }

    function _grantMaxim(address account) private returns(uint256) {
        _tokenId.increment();

        CoreNFT storage newCoreNFT = global.CoreNFTs[_tokenId.current()];
        newCoreNFT.id = _tokenId.current();
        newCoreNFT.classId = 2;
        newCoreNFT.grantBlock = block.number;
        global.CoreNFTsByOwner[account].push(newCoreNFT.id); 
        global.TotalNFTsByClass[2]++;

        _mint(account, newCoreNFT.id);
        emit CoreNFTGranted(newCoreNFT.id, 2, account, 0);

        return newCoreNFT.id;
    }


    function batchBoostAccount(address account, uint256[] memory boosterIds) public whenNotPaused returns(uint16, uint256) {
        uint256 tokenId = 0;
        for(uint256 t=1;t<currentSupply();t++) {
            if (ownerOf(t) == account && (global.CoreNFTs[t].classId == 1 || global.CoreNFTs[t].classId == 2)) {
                tokenId = t;
                break;
            }
        }

        if (tokenId == 0) {
            tokenId = _grantMaxim(account); 
        }

        return batchBoostToken(tokenId, boosterIds);
    }

    function batchBoostToken(uint256 tokenId, uint256[] memory boosterIds) public whenNotPaused returns(uint16, uint256) {
        uint16 totalBasisPoints;
        uint256 totalTokensDue;
        for(uint16 b=0;b<boosterIds.length;b++) {
            // If account does not have Nexus, a Maxim token is added to their account with the first boost
            (uint16 basisPoints, uint256 tokensDue) = boostToken(tokenId, boosterIds[b]);
            totalBasisPoints += basisPoints;
            totalTokensDue += tokensDue;
        }
        return (totalBasisPoints, totalTokensDue);
    }

    function boostToken(uint256 tokenId, uint256 boosterId) public whenNotPaused returns(uint16, uint256)  {  

        require(boosterContract.ownerOf(boosterId) == msg.sender, "Caller does not own booster");
            
        VitruveoBoosterNFT.boosterInfo memory booster = boosterContract.getBoosterInfo(boosterId);
        require(!booster.isBoosted, "Booster already used");

        CoreNFT storage coreNFT = global.CoreNFTs[tokenId];    
        require(coreNFT.classId == 1 || coreNFT.classId == 2, "Token not boostable");
        require(!coreNFT.isRevoked, "Token was revoked");

        // Removed 25 boost maximum
        // require(coreNFT.boosts < 25, "Maximum token boost reached");        
        // require(booster.basisPoints == 100 ? coreNFT.boostBasisPoints + booster.basisPoints < 25 : true, "Maximum boosts applied");


        boosterContract.consumeBoost(boosterId);
        if (booster.basisPoints > 0) {
            coreNFT.boostBasisPoints += uint16(booster.basisPoints);
            coreNFT.boosts++;
        }

        (bool boosted, ) = payable(ownerOf(coreNFT.id)).call{value: booster.tokensDue * DECIMALS}("");
        require(boosted, "Failed to boost due to insufficient funds");        

        return (coreNFT.boostBasisPoints, booster.tokensDue * DECIMALS);
    }


    function calculateGrantClaimAmounts(uint256 tokenId, bool includeRebase) public view returns(uint256, uint256, uint256) {
        return calculateGrantClaimAmounts(tokenId, includeRebase, block.number);
    }

    function calculateGrantClaimAmounts(uint256 tokenId, bool includeRebase, uint256 blockNumber) public view returns(uint256, uint256, uint256) {

        CoreNFT memory coreNFT = global.CoreNFTs[tokenId];
        CalcData memory ch;

        // 1) Calculate unlocked amount 
        ch.unlockAmountDue = (coreNFT.grantAmount * coreNFT.unlockBasisPoints) / 10000;

        if (coreNFT.grantBlock <= blockNumber) {

            // 2) Actual grant amount is balance after subtracting unlocked amount
            ch.adjustedGrantAmount = coreNFT.grantAmount - ch.unlockAmountDue;

            // 3) Number of months of vesting that have elapsed. 
            ch.months = (blockNumber - coreNFT.grantBlock) / BLOCKS_IN_MONTH;
            
            // 4) Vested amount is only available after lock period
            if (ch.months > coreNFT.lockMonths && coreNFT.vestingMonths > 0) {
                uint256 claimBasisPoints = ((ch.months * 10000) / coreNFT.vestingMonths) + (coreNFT.boostBasisPoints * ch.months);
                if (claimBasisPoints > 10000) {
                    claimBasisPoints = 10000;
                }
                ch.vestedAmountDue = (ch.adjustedGrantAmount * claimBasisPoints) / 10000;
            }
        }

        // 5) If there has already been an advance given then don't allow a claim if advance was more than unlock amount plus vested amount
        ch.totalAmountDue = ch.unlockAmountDue + ch.vestedAmountDue;
        if (ch.totalAmountDue > coreNFT.claimedGrantAmount) {
            ch.grantClaimAmount = ch.totalAmountDue - coreNFT.claimedGrantAmount;
        }

        // Can't withdraw more than deposit
        if (ch.grantClaimAmount > coreNFT.depositAmount) {
            ch.grantClaimAmount = coreNFT.depositAmount;
        }

        //Fix 100% VTRO claim issue
        if (coreNFT.depositAmount == DECIMALS) {
            ch.grantClaimAmount = 0;
        }

        // 6) If rebase calculation is requested, calculate it based on the amount deposited
        if (includeRebase) {
            if (address(this).balance > totalCurrentDepositBalance + BOOSTER_ESCROW) {
                ch.rebaseDifference = address(this).balance - totalCurrentDepositBalance - BOOSTER_ESCROW;
                ch.rebaseShare = (coreNFT.depositAmount * SCALER) / global.totalDepositBalance;
                ch.rebasedAmountDue = (ch.rebaseDifference * ch.rebaseShare) / SCALER;
                if (ch.rebasedAmountDue > coreNFT.claimedRebaseAmount) {
                    ch.rebaseClaimAmount = ch.rebasedAmountDue - coreNFT.claimedRebaseAmount;
                }        
            }
        }

        return (ch.grantClaimAmount, ch.rebaseClaimAmount, ch.months);
    }

    // Anyone can call claim but unlocked and vested coins are always 
    // sent to account that is token owner at the time of the claim
    function claim(uint256 tokenId) external whenNotPaused returns(uint256, uint256, uint256) {
        CoreNFT storage coreNFT = global.CoreNFTs[tokenId];    
        require(coreNFT.classId > 0, "Token ID does not exist");
        require(!coreNFT.isRevoked, "Token was revoked");
       
        (uint256 claimAmount, uint256 rebaseClaimAmount, uint256 months) = calculateGrantClaimAmounts(tokenId, false);
        uint256 claimTotal = claimAmount + rebaseClaimAmount;
        if (claimTotal > 0) {
            totalCurrentDepositBalance -= claimAmount;
            coreNFT.claimedGrantAmount += claimAmount;
            coreNFT.claimedRebaseAmount += rebaseClaimAmount;

            require(address(this).balance >= claimTotal, "Insufficient contract balance for claim");

            (bool claimed, ) = payable(ownerOf(tokenId)).call{value: claimTotal}("");
            require(claimed, "Failed to claim");        

            emit CoreNFTFundsClaimed(tokenId, claimAmount, rebaseClaimAmount, claimTotal);
        }

        return (claimAmount, rebaseClaimAmount, months);
    }

    // function revokeCoreNFT(uint256 tokenId) external whenNotPaused onlyRole(GRANTER_ROLE) {

    //     CoreNFT storage coreNFT = global.CoreNFTs[tokenId];    
    //     require(coreNFT.classId > 0, "Token ID does not exist");
    //     require(!coreNFT.isRevoked, "Token was revoked");
    //     require(coreNFT.isRevocable, "Token grant is not revocable");

    //     coreNFT.isRevoked = true;
    //     uint256 refundAmount = coreNFT.depositAmount - coreNFT.claimedGrantAmount;
    //     totalCurrentDepositBalance -= refundAmount;
    //     global.totalDepositBalance -= refundAmount;

    //     (bool claimed, ) = payable(msg.sender).call{value: refundAmount}("");
    //     require(claimed, "Failed to refund");        

    //     emit CoreNFTRevoked(tokenId);
    // }

    // Processes a claim resulting from a grant
    // This would be unlocked and vested coins
    function _processGrantClaim(CoreNFT storage coreNFT, address account) internal {

        // Calculate claim amount
        (uint256 claimAmount, , ) = calculateGrantClaimAmounts(coreNFT.id, false);
        coreNFT.claimedGrantAmount = claimAmount;

        // Update accumulators
        global.CoreNFTClasses[coreNFT.classId].totalGrants += coreNFT.grantAmount;
        global.totalDepositBalance += coreNFT.depositAmount;
        totalCurrentDepositBalance += coreNFT.depositAmount - claimAmount;
        
        // Transfer claim amount to user wallet
        (bool claimed, ) = payable(account).call{value: claimAmount}("");
        require(claimed, "Failed to claim");        

    }
    
    // Checks to see if account is allowed to have an NFT of this classId
    function isGrantAllowed(address account, uint256 classId) public view returns(bool) {
        // If account owns at least one Core NFT
        if (global.CoreNFTsByOwner[account].length > 0) {
            // Loop through each and get the class and check its allowMultiple property
            for(uint f=0; f<global.CoreNFTsByOwner[account].length; f++) {
                CoreNFT memory coreNFT = global.CoreNFTs[global.CoreNFTsByOwner[account][f]];
                if (coreNFT.classId == classId) {
                    CoreNFTClass memory coreNFTClass = global.CoreNFTClasses[classId];
                    return coreNFTClass.allowMultiple;
                }
            }
            return true;
        } else {
            return true;
        }
    }

    uint256 public lastItem; // Deprecated

    function getAccountTokens(address account) public view returns(CoreNFT[] memory){

        uint256[] memory nfts = global.CoreNFTsByOwner[account];
        CoreNFT[] memory coreNFTs = new CoreNFT[](nfts.length);
        for(uint f=0; f<nfts.length; f++) {
            coreNFTs[f] = global.CoreNFTs[nfts[f]];
        }
        return coreNFTs;
    }

    function getCoreTokenInfo(uint256 id) public view  returns (CoreNFT memory)
    {
        return global.CoreNFTs[id];
    }

    function getCoreClassInfo(uint256 id) public view  returns (CoreNFTClass memory)
    {
        return global.CoreNFTClasses[id];
    }

    function tokenURI(uint256 tokenId) override public view returns (string memory){

        CoreNFT memory coreNFT = global.CoreNFTs[tokenId];    
        require(coreNFT.classId > 0, "Token ID does not exist");

        CoreNFTClass memory coreNFTClass = global.CoreNFTClasses[coreNFT.classId];

	    string memory json = Base64Upgradeable.encode(bytes(string(abi.encodePacked('{"name": "', coreNFTClass.name, '", "description": "Vitruveo Core NFT", "image": "', global.classImageURI, coreNFTClass.name, '.png"}'))));
	
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public override isTransferAllowed(tokenId) whenNotPaused {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override isTransferAllowed(tokenId) whenNotPaused {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
        _safeTransfer(from, to, tokenId, data);
    }

    function adminTransferFrom(address from, address to, uint256 tokenId) public whenNotPaused onlyRole(GRANTER_ROLE) {
        _transfer(from, to, tokenId);
    }

    modifier isTransferAllowed(uint256 tokenId) {

        CoreNFT memory coreNFT = global.CoreNFTs[tokenId];    
        require(coreNFT.classId > 0, "Token ID does not exist");

        CoreNFTClass memory coreNFTClass = global.CoreNFTClasses[coreNFT.classId];
        require(coreNFTClass.isTransferable, "Token is not transferable");

        _;
    }

    function currentSupply() public view returns (uint256) {
        return _tokenId.current();
    }

    // Registers a Core NFT Class
    // function registerCoreClass(
    //     uint256 id,
    //     string memory name,
    //     bool isTransferable,
    //     bool allowMultiple
    // ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused returns (CoreNFTClass memory) {

    //     global.CoreNFTClasses[id] = CoreNFTClass(id, name, isTransferable, allowMultiple, true, 0);
  
    //     return global.CoreNFTClasses[id];
    // }

    // Updates a Core NFT Class
    function updateCoreClass(
        uint256 id,
        bool isTransferable,
        bool allowMultiple
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {

        global.CoreNFTClasses[id].isTransferable = isTransferable;
        global.CoreNFTClasses[id].allowMultiple = allowMultiple;
        
    }

    function setBoosterContract(address contractAddress) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        boosterContract = VitruveoBoosterNFT(contractAddress);
    }

    function setBlocksInMonth(uint blocks) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(blocks > 0, "Invalid blocks value.");
        BLOCKS_IN_MONTH = blocks;
    }

    function setTotalCurrentDepositBalance() public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        totalCurrentDepositBalance = address(this).balance;
    }

    function setClassImageURI(string memory uri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        global.classImageURI = uri;
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

    function transferVTRU(address account, uint amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(payable(account).send(amount));
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
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Upgrades start here

    // Staking
    uint public constant BLOCKS_PER_YEAR = 6307200;
    struct StakeInfo {
        uint endBlock;
        uint balance;
    }
    mapping(address => StakeInfo[]) public stakes;
    uint public stakeUnlockedTotal;
    uint public stakeLockedTotal;

    // event VTRUStaked(address indexed account, uint amount, uint yearCount);

    // function stake(
    //                 address account,
    //                 uint yearCount
    //             ) public payable whenNotPaused {
        
    //     require(account != address(0), "Invalid account address");

    //     stakes[account].push(StakeInfo(BLOCKS_PER_YEAR * yearCount, msg.value));
    //     stakeUnlockedTotal += msg.value / DECIMALS;
    //     emit VTRUStaked(account, msg.value, yearCount);
    // }
}

