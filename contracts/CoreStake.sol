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
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Structs
    struct StakeTerm {
        uint epochs; // Number of epochs (days)
        uint aprBasisPoints; // 100 basis points = 1%
    }

    struct StakeTermInfo {
        uint amount;
        uint startBlock;
        uint stakeTermID;
    }

    struct StakeInfo {
        uint stakeId;
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

    // Events
    event Staked(address indexed user, uint amount, uint stakeTermID, uint startBlock);
    event Unstaked(address indexed user, uint amount, uint reward);
    event StakeRedeemed(address indexed user, uint amount, uint reward);

    // Initialization
    function initialize() public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(UPGRADER_ROLE, msg.sender);
        _setupRole(REDEEMER_ROLE, msg.sender);
        nextStakeTermId = 1;

        // Add predefined stake terms
        addStakeTerm(60, 1800);  // 60 epochs (days), 18% APR
        addStakeTerm(90, 2300);  // 90 epochs (days), 23% APR
        addStakeTerm(120, 3000); // 120 epochs (days), 30% APR
        addStakeTerm(150, 3900); // 150 epochs (days), 39% APR
        addStakeTerm(180, 5000); // 180 epochs (days), 50% APR
    }

    // Write Functions
    function stake(uint stakeTermID) external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Amount must be greater than zero");
        require(stakeTerms[stakeTermID].epochs > 0, "Invalid stake term");

        userStakes[msg.sender].push(StakeTermInfo({
            amount: msg.value,
            startBlock: block.number,
            stakeTermID: stakeTermID
        }));

        totalStaked += msg.value;
        totalStakesCreated++;
        activeStakes++;
        if (userStakes[msg.sender].length == 1) {
            totalUsers++;
        }

        emit Staked(msg.sender, msg.value, stakeTermID, block.number);
    }

    function unstake() external nonReentrant whenNotPaused {
        unstakeUser(msg.sender);
    }

    function unstakeAdmin(address user) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        unstakeUser(user);
    }

    // Internal Function for Unstaking
    function unstakeUser(address account) internal {
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

    // Public Functions for Reward Calculation and Eligibility Check
    function calculatePartialReward(uint amount, uint startBlock, uint endBlock, uint stakeTermID) public view returns (uint) {
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

    function getUserStakesInfo(address account, bool unstakeNow) external view returns (StakeInfo[] memory) {
        StakeTermInfo[] storage stakesArray = userStakes[account];
        StakeInfo[] memory stakeInfos = new StakeInfo[](stakesArray.length);

        for (uint i = 0; i < stakesArray.length; i++) {
            StakeTermInfo storage stakeInfo = stakesArray[i];
            uint endBlock = stakeInfo.startBlock + (stakeTerms[stakeInfo.stakeTermID].epochs * ONE_EPOCH);
            if (unstakeNow && block.number < endBlock) {
                endBlock = block.number; // Unstake partially now
            }
            bool eligibleToUnstake = block.number >= endBlock && stakeInfo.amount > 0;
            uint reward = eligibleToUnstake ? calculatePartialReward(stakeInfo.amount, stakeInfo.startBlock, endBlock, stakeInfo.stakeTermID) : 0;
            uint unstakeAmount = stakeInfo.amount + reward;

            stakeInfos[i] = StakeInfo({
                stakeId: i,
                eligibleToUnstake: eligibleToUnstake,
                unstakeAmount: unstakeAmount
            });
        }
        return stakeInfos;
    }


    function unstakeRedeemPreview(address account, uint amount) public view returns(uint earlyUnstaked, uint earlyReward, bool allowRedeem) {

        StakeTermInfo[] memory stakesArray = userStakes[account];
        uint remainingAmount = amount;

        for (uint i = 0; i < stakesArray.length; i++) {
            uint endBlock = stakesArray[i].startBlock + (stakeTerms[stakesArray[i].stakeTermID].epochs * ONE_EPOCH);
            if (block.number < endBlock && stakesArray[i].amount > 0) {
                endBlock = block.number;
                uint reward = calculatePartialReward(stakesArray[i].amount, stakesArray[i].startBlock, endBlock, stakesArray[i].stakeTermID);
                uint unstakeAmount = stakesArray[i].amount + reward;

                if (earlyUnstaked + unstakeAmount > remainingAmount) {
                    uint partialAmount = remainingAmount - earlyUnstaked;
                    uint partialReward = (partialAmount * reward) / unstakeAmount;

                    earlyUnstaked += partialAmount;
                    earlyReward += partialReward;
                    break;
                } else {
                    earlyUnstaked += unstakeAmount;
                    earlyReward += reward;
                }
            }

            if (earlyUnstaked >= amount) {
                break;
            }
        }
        allowRedeem = earlyUnstaked >= amount;
    }

    function unstakeRedeem(address account, uint amount) public nonReentrant whenNotPaused {
        require(hasRole(REDEEMER_ROLE, msg.sender), "Must have redeemer role to redeem");

        uint earlyUnstaked = 0;
        uint earlyReward = 0;

        StakeTermInfo[] storage stakesArray = userStakes[account];
        uint remainingAmount = amount;

        for (uint i = 0; i < stakesArray.length; i++) {
            uint endBlock = stakesArray[i].startBlock + (stakeTerms[stakesArray[i].stakeTermID].epochs * ONE_EPOCH);
            if (block.number < endBlock && stakesArray[i].amount > 0) {
                endBlock = block.number;
                uint reward = calculatePartialReward(stakesArray[i].amount, stakesArray[i].startBlock, endBlock, stakesArray[i].stakeTermID);
                uint unstakeAmount = stakesArray[i].amount + reward;

                if (earlyUnstaked + unstakeAmount > remainingAmount) {
                    uint partialAmount = remainingAmount - earlyUnstaked;
                    uint partialReward = (partialAmount * reward) / unstakeAmount;

                    earlyUnstaked += partialAmount;
                    earlyReward += partialReward;

                    totalStaked -= partialAmount;

                    stakesArray[i].amount -= partialAmount;
                    break;
                } else {
                    earlyUnstaked += unstakeAmount;
                    earlyReward += reward;

                    totalStaked -= stakesArray[i].amount;
                    activeStakes--;

                    stakesArray[i].amount = 0; // Mark as withdrawn by setting amount to 0
                }
            }

            if (earlyUnstaked >= amount) {
                break;
            }
        }

        require(earlyUnstaked >= amount, "Insufficient ineligible stakes to fulfill the amount");

        totalRewardDistributed += earlyReward;

        // Transfer the aggregated amount (from early unstaked) to the admin caller
        payable(msg.sender).sendValue(earlyUnstaked);

        emit StakeRedeemed(account, earlyUnstaked, earlyReward);
    }

    // Admin Functions
    function addStakeTerm(uint epochs, uint aprBasisPoints) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        stakeTerms[nextStakeTermId] = StakeTerm({
            epochs: epochs,
            aprBasisPoints: aprBasisPoints
        });
        nextStakeTermId++;
    }

    function importUserStakes(
        address user,
        uint[] calldata amounts,
        uint[] calldata startBlocks,
        uint[] calldata stakeTermIDs
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(
            amounts.length == startBlocks.length &&
            amounts.length == stakeTermIDs.length,
            "Input arrays must have the same length"
        );

        for (uint i = 0; i < amounts.length; i++) {
            require(stakeTerms[stakeTermIDs[i]].epochs > 0, "Invalid stake term");

            userStakes[user].push(StakeTermInfo({
                amount: amounts[i],
                startBlock: startBlocks[i],
                stakeTermID: stakeTermIDs[i]
            }));

            totalStaked += amounts[i];
            totalStakesCreated++;
            activeStakes++;
            if (userStakes[user].length == 1) {
                totalUsers++;
            }
        }
    }

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
        return (
            totalStaked,
            totalRewardDistributed,
            totalStakesCreated,
            activeStakes,
            totalUsers,
            nextStakeTermId - 1
        );
    }

    // Upgrade Authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    receive() external payable {}
}

       
