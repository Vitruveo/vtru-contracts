/*
 *   @title    VTRU Airdrop Staking
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

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract CoreStake is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using AddressUpgradeable for address payable;

    // Constants
    uint public constant ONE_EPOCH = 17280; // One epoch equals one day (in blocks)
    uint public constant DAYS_IN_YEAR = 365; // Days in a year
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Structs
    struct StakeTerm {
        uint epochs; // Number of epochs (days)
        uint aprBasisPoints; // 100 basis points = 1%
    }

    struct StakeTermFull {
        uint id;
        uint epochs; // Number of epochs (days)
        uint aprBasisPoints; // 100 basis points = 1%
        bool active;
    }

    struct StakeTermInfo {
        uint amount;
        uint startBlock;
        uint stakeTermID;
    }

    struct StakeDetailInfo {
        uint stakeId;
        uint amount;
        uint startBlock;
        uint stakeTermID;
        uint unstakeAmount;
        bool eligibleToUnstake;
    }

    // Mappings
    mapping(uint => StakeTerm) public stakeTerms;
    mapping(address => StakeTermInfo[]) public userStakes;

    // Individual Variables
    uint public totalStaked;
    uint public totalRewardDistributed;
    uint public totalStakesCreated;
    uint public activeStakes;
    uint public totalUsers;
    uint public nextStakeTermId;

    mapping(uint => bool) public activeStakeTerms;

    
    // Events
    event Staked(address indexed user, uint amount, uint stakeTermID, uint startBlock);
    event Unstaked(address indexed user, uint amount, uint reward);

    function initialize() public initializer {
        // __AccessControl_init();
        // __ReentrancyGuard_init();
        // __Pausable_init();
        // __UUPSUpgradeable_init();
        // _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // _setupRole(UPGRADER_ROLE, msg.sender);
        // _setupRole(REDEEMER_ROLE, msg.sender);
        // nextStakeTermId = 1;

        // // Add predefined stake terms
        // addStakeTerm(60, 1800);  // 60 epochs (days), 18% APR
        // addStakeTerm(90, 2300);  // 90 epochs (days), 23% APR
        // addStakeTerm(120, 3000); // 120 epochs (days), 30% APR
        // addStakeTerm(150, 3900); // 150 epochs (days), 39% APR
        // addStakeTerm(180, 5000); // 180 epochs (days), 50% APR
    }

    function stake(uint stakeTermID) external payable {
        require(msg.value > 0, "Amount must be greater than zero");

        _stake(msg.sender, msg.value, stakeTermID, block.number);
    }

    function stakeFor(address account, uint stakeTermID) public payable {
        require(msg.value > 0, "Amount must be greater than zero");

        _stake(account, msg.value, stakeTermID, block.number);
    }

    function stakeAdmin(address[] memory accounts, uint stakeTermID, uint blockNumber) public payable onlyRole(DEFAULT_ADMIN_ROLE){
        require(msg.value > 0, "Amount must be greater than zero");
        require(accounts.length > 0, "No accounts defined");

        uint amountEach = msg.value / accounts.length;
        for(uint a=0; a<accounts.length; a++) {
            _stake(accounts[a], amountEach, stakeTermID, blockNumber);
        }
    }

    function stakeAdminFunded(address account, uint stakeTermID, uint blockNumber, uint amount) public onlyRole(DEFAULT_ADMIN_ROLE){
        _stake(account, amount, stakeTermID, blockNumber);
    }

    function _stake(address account, uint amount, uint stakeTermID, uint blockNumber) internal nonReentrant whenNotPaused {
        require(stakeTerms[stakeTermID].epochs > 0, "Invalid stake term");
        require(activeStakeTerms[stakeTermID] == true, "Stake Term not active");

        userStakes[account].push(StakeTermInfo({
            amount: amount,
            startBlock: blockNumber,
            stakeTermID: stakeTermID
        }));

        totalStaked += amount;
        totalStakesCreated++;
        activeStakes++;
        if (userStakes[account].length == 1) {
            totalUsers++;
        }

        emit Staked(account, amount, stakeTermID, blockNumber);
    }

    function unstake() external nonReentrant whenNotPaused {
        _unstake(msg.sender);
    }

    function unstakeAdmin(address account) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        _unstake(account);
    }

    function _unstake(address account) internal {
        uint totalUnstakedAmount = 0;
        uint totalReward = 0;
        StakeTermInfo[] storage stakesArray = userStakes[account];
        
        for (uint i = 0; i < stakesArray.length; i++) {
            (bool eligible, uint unstakeAmount, uint reward) = calculateFullReward(
                stakesArray[i].amount, stakesArray[i].startBlock, stakesArray[i].stakeTermID
            );
            if (eligible) {
                totalReward += reward;
                totalUnstakedAmount += unstakeAmount;

                totalStaked -= stakesArray[i].amount;
                activeStakes--;
                stakesArray[i].amount = 0; // Mark as withdrawn by setting amount to 0
            }
        }

        require(totalUnstakedAmount > 0, "No eligible stakes to unstake");
        require(totalUnstakedAmount <= totalStaked + totalReward, "Cannot withdraw more than staked amount plus rewards");
        totalRewardDistributed += totalReward;
        payable(account).sendValue(totalUnstakedAmount);

        emit Unstaked(account, totalUnstakedAmount - totalReward, totalReward);
    }

    function calculatePartialReward(uint amount, uint startBlock, uint endBlock, uint stakeTermID) public view returns (uint) {
        if (endBlock == 0) {
            endBlock = block.number;
        }
        uint totalEpochs = (endBlock - startBlock) / ONE_EPOCH; // Calculate the number of complete epochs
        uint rewardPerEpoch = (amount * stakeTerms[stakeTermID].aprBasisPoints) / (DAYS_IN_YEAR * 10000);
        return rewardPerEpoch * totalEpochs;
    }

    function calculateFullReward(uint amount, uint startBlock, uint stakeTermID) public view returns (bool, uint, uint) {
        uint endBlock = startBlock + (stakeTerms[stakeTermID].epochs * ONE_EPOCH);
        if (block.number >= endBlock && amount > 0) {
            uint reward = calculatePartialReward(amount, startBlock, endBlock, stakeTermID);
            uint unstakeAmount = amount + reward;
            return (true, unstakeAmount, reward);
        }
        return (false, 0, 0);
    }

    function getUserStakesInfo(address account, bool unstakeNow) external view returns (StakeDetailInfo[] memory) {
        StakeTermInfo[] storage stakesArray = userStakes[account];
        StakeDetailInfo[] memory stakeInfos = new StakeDetailInfo[](stakesArray.length);

        for (uint i = 0; i < stakesArray.length; i++) {
            StakeTermInfo storage stakeInfo = stakesArray[i];
            uint endBlock = stakeInfo.startBlock + (stakeTerms[stakeInfo.stakeTermID].epochs * ONE_EPOCH);
            if (unstakeNow && block.number < endBlock) {
                endBlock = block.number; // Unstake partially now
            }
            bool eligibleToUnstake = block.number >= endBlock && stakeInfo.amount > 0;
            uint reward = eligibleToUnstake ? calculatePartialReward(stakeInfo.amount, stakeInfo.startBlock, endBlock, stakeInfo.stakeTermID) : 0;
            uint unstakeAmount = stakeInfo.amount + reward;

            stakeInfos[i] = StakeDetailInfo({
                stakeId: i,
                amount: stakeInfo.amount,
                startBlock: stakeInfo.startBlock,
                stakeTermID: stakeInfo.stakeTermID,
                eligibleToUnstake: eligibleToUnstake,
                unstakeAmount: unstakeAmount
            });
        }
        return stakeInfos;
    }

    function addStakeTerm(uint epochs, uint aprBasisPoints) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        stakeTerms[nextStakeTermId] = StakeTerm({
            epochs: epochs,
            aprBasisPoints: aprBasisPoints
        });
        nextStakeTermId++;
    }

    function changeStakeTerm(uint stakeTermId, uint epochs, uint aprBasisPoints) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        stakeTerms[stakeTermId].epochs = epochs;
        stakeTerms[stakeTermId].aprBasisPoints = aprBasisPoints;
    }

    function setStakeTermStatus(uint stakeTermId, bool isActive) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        activeStakeTerms[stakeTermId] = isActive;
    }

    function getStakeTerms() public view returns(StakeTermFull[] memory) {

        StakeTermFull[] memory stakeTermsArr = new StakeTermFull[](nextStakeTermId);
        for(uint s=1;s<stakeTermsArr.length;s++) { 

            stakeTermsArr[s] = StakeTermFull({
                id: s,
                epochs: stakeTerms[s].epochs,
                aprBasisPoints: stakeTerms[s].aprBasisPoints,
                active: activeStakeTerms[s]
            });    
        }

        return stakeTermsArr;
    }

    // function importUserStakes(
    //     address user,
    //     uint[] calldata amounts,
    //     uint[] calldata startBlocks,
    //     uint[] calldata stakeTermIDs
    // ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
    //     require(
    //         amounts.length == startBlocks.length &&
    //         amounts.length == stakeTermIDs.length,
    //         "Input arrays must have the same length"
    //     );

    //     for (uint i = 0; i < amounts.length; i++) {
    //         require(stakeTerms[stakeTermIDs[i]].epochs > 0, "Invalid stake term");

    //         userStakes[user].push(StakeTermInfo({
    //             amount: amounts[i],
    //             startBlock: startBlocks[i],
    //             stakeTermID: stakeTermIDs[i]
    //         }));

    //         totalStaked += amounts[i];
    //         totalStakesCreated++;
    //         activeStakes++;
    //         if (userStakes[user].length == 1) {
    //             totalUsers++;
    //         }
    //     }
    // }

    function withdrawVtru() external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        payable(msg.sender).sendValue(address(this).balance);
    }

    // Pausing Functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // Stats Function
    function stats() external view returns (
        uint totalStakedAmount,
        uint totalRewardDist,
        uint totalStakes,
        uint activeStakesCount,
        uint totalUsersCount,
        uint totalStakingTerms
    ) {
        totalStakedAmount = totalStaked;
        totalRewardDist = totalRewardDistributed;
        totalStakes = totalStakesCreated;
        activeStakesCount = activeStakes;
        totalUsersCount = totalUsers;
        totalStakingTerms = nextStakeTermId - 1;
    }

    // Upgrade Authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    receive() external payable {}
}

       
