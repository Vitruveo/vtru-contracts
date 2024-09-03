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

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VibePool is AccessControl, Pausable, Initializable {
    using SafeMath for uint256;

    struct Deposit {
        uint256 amount; // Amount of VTRU deposited (including bonus)
        uint256 epochNumber; // Epoch number when the deposit was made
        uint256 claimed; // Amount of revenue already claimed for this deposit
    }

    struct Pool {
        mapping(address => Deposit[]) deposits; // Tracks each depositor's deposits
        uint256 totalDeposited; // Total VTRU deposited in the pool (including bonuses)
        RevenueCheckpoint[] revenueHistory; // Array to store cumulative revenue at each epoch checkpoint
        bool bonusEnabled; // Flag to enable or disable the bonus for this pool
        uint256 totalRevenue; // Total revenue deposited into the pool
        uint256 totalClaimed; // Total revenue claimed from the pool
        address[] users; // List of users in this pool
    }

    struct RevenueCheckpoint {
        uint256 epochNumber; // Epoch number at which revenue was received
        uint256 totalRevenue; // Total cumulative revenue up to this epoch
    }

    mapping(uint256 => Pool) public pools; // Mapping of poolId to Pool struct

    event DepositMade(address indexed user, uint256 poolId, uint256 amount, uint256 epochNumber);
    event RevenueClaimed(address indexed user, uint256 poolId, uint256 amount);
    event RevenueReceived(uint256 poolId, uint256 amount, uint256 epochNumber);
    event DepositTransferred(address indexed from, address indexed to, uint256 poolId, uint256 totalDepositsTransferred);

    function initialize() initializer public {
    }

    // Function to create a new pool
    function createPool(uint256 poolId, bool bonusEnabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(pools[poolId].totalDeposited == 0, "Pool already exists");

        pools[poolId].bonusEnabled = bonusEnabled;
    }

    // Function to toggle the bonus on or off for a specific pool
    function toggleBonus(uint256 poolId, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pools[poolId].bonusEnabled = enabled;
    }

    // Public function to check if a deposit is allowed
    function isDepositAllowed(uint256 poolId, address user) public view returns (bool) {
        if (poolId == 2) { // Creator pool
            // Placeholder for creator check logic
            return true; // For now, allow deposits
        }

        // Default behavior: allow deposits
        return true;
    }

    // Function for users to deposit VTRU into a specific pool
    function deposit(uint256 poolId) external payable whenNotPaused {
        require(isDepositAllowed(poolId, msg.sender), "Deposit not allowed");
        require(msg.value > 0, "Deposit amount must be greater than zero");

        uint256 effectiveDeposit = msg.value;
        uint256 currentEpoch = getCurrentEpoch();

        if (pools[poolId].bonusEnabled) {
            effectiveDeposit = calculateEffectiveDeposit(msg.value);
        }

        pools[poolId].deposits[msg.sender].push(Deposit({
            amount: effectiveDeposit,
            epochNumber: currentEpoch,
            claimed: 0
        }));

        pools[poolId].totalDeposited = pools[poolId].totalDeposited.add(effectiveDeposit);
        pools[poolId].totalRevenue = pools[poolId].totalRevenue.add(msg.value);

        // Add user to the pool if not already added
        if (pools[poolId].deposits[msg.sender].length == 1) {
            pools[poolId].users.push(msg.sender);
        }

        emit DepositMade(msg.sender, poolId, effectiveDeposit, currentEpoch);
    }

    // Public function to calculate the effective deposit including bonus
    function calculateEffectiveDeposit(uint256 depositAmount) public pure returns (uint256) {
        uint256 bonusPercentage = 0;
        uint256 cappedDeposit = depositAmount;

        if (depositAmount >= 1000) {
            bonusPercentage = 100; // Cap at 100%
        } else {
            bonusPercentage = (depositAmount.div(100)).mul(10); // 10% bonus for each 100 VTRU
        }

        cappedDeposit = depositAmount.add(depositAmount.mul(bonusPercentage).div(100));

        return cappedDeposit;
    }

    // Function to transfer all deposits to another user within a specific pool
    function transferAllDeposits(uint256 poolId, address to) external whenNotPaused {
        require(to != address(0), "Cannot transfer to zero address");
        require(pools[poolId].deposits[msg.sender].length > 0, "No deposits to transfer");

        // Transfer all deposits from the sender to the recipient within the pool
        for (uint256 i = 0; i < pools[poolId].deposits[msg.sender].length; i++) {
            pools[poolId].deposits[to].push(pools[poolId].deposits[msg.sender][i]);
        }

        // Clear all deposits from the sender within the pool
        delete pools[poolId].deposits[msg.sender];

        emit DepositTransferred(msg.sender, to, poolId, pools[poolId].deposits[to].length);
    }

    // Function to deposit revenue into a specific pool
    function depositRevenue(uint256 poolId) external payable {
        require(msg.value > 0, "Revenue amount must be greater than zero");

        uint256 currentEpoch = getCurrentEpoch();

        uint256 newTotalRevenue = (pools[poolId].revenueHistory.length > 0)
            ? pools[poolId].revenueHistory[pools[poolId].revenueHistory.length - 1].totalRevenue.add(msg.value)
            : msg.value;

        if (pools[poolId].revenueHistory.length == 0 || pools[poolId].revenueHistory[pools[poolId].revenueHistory.length - 1].epochNumber != currentEpoch) {
            pools[poolId].revenueHistory.push(RevenueCheckpoint({
                epochNumber: currentEpoch,
                totalRevenue: newTotalRevenue
            }));
        } else {
            pools[poolId].revenueHistory[pools[poolId].revenueHistory.length - 1].totalRevenue = newTotalRevenue;
        }

        pools[poolId].totalRevenue = pools[poolId].totalRevenue.add(msg.value);

        emit RevenueReceived(poolId, msg.value, currentEpoch);
    }

    // Function for users to claim their share of the revenue from a specific pool
    function claimRevenue(uint256 poolId) external whenNotPaused {
        uint256 claimable = calculateClaimableRevenue(poolId, msg.sender);
        require(claimable > 0, "No claimable revenue at this time");

        for (uint256 i = 0; i < pools[poolId].deposits[msg.sender].length; i++) {
            pools[poolId].deposits[msg.sender][i].claimed = calculateClaimableForDeposit(poolId, msg.sender, i);
        }

        pools[poolId].totalClaimed = pools[poolId].totalClaimed.add(claimable);

        payable(msg.sender).transfer(claimable);

        emit RevenueClaimed(msg.sender, poolId, claimable);
    }

    // Public function to calculate the claimable revenue for a user across all deposits in a specific pool
    function calculateClaimableRevenue(uint256 poolId, address user) public view returns (uint256) {
        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < pools[poolId].deposits[user].length; i++) {
            totalClaimable = totalClaimable.add(calculateClaimableForDeposit(poolId, user, i));
        }
        return totalClaimable;
    }

    // Public function to calculate claimable revenue for a specific deposit in a specific pool
    function calculateClaimableForDeposit(uint256 poolId, address user, uint256 index) public view returns (uint256) {
        Deposit storage userDeposit = pools[poolId].deposits[user][index];

        uint256 depositEpoch = userDeposit.epochNumber;
        uint256 totalRevenueAtDeposit = getTotalRevenueAtEpoch(poolId, depositEpoch);

        uint256 userShare = (userDeposit.amount * (totalRevenueAtDeposit - userDeposit.claimed)) / pools[poolId].totalDeposited;

        return userShare;
    }

    // Public function to get total cumulative revenue at a specific epoch in a specific pool
    function getTotalRevenueAtEpoch(uint256 poolId, uint256 epochNumber) public view returns (uint256) {
        if (pools[poolId].revenueHistory.length == 0) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = pools[poolId].revenueHistory.length - 1;

        // Perform binary search for efficiency
        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (pools[poolId].revenueHistory[mid].epochNumber <= epochNumber) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return pools[poolId].revenueHistory[low].totalRevenue;
    }

    // Public function to retrieve a specified number of revenue checkpoints starting from a given epoch number in a specific pool
    function getRevenueCheckpoints(uint256 poolId, uint256 startEpoch, uint256 count) public view returns (RevenueCheckpoint[] memory) {
        uint256 startIdx = pools[poolId].revenueHistory.length;
        for (uint256 i = pools[poolId].revenueHistory.length; i > 0; i--) {
            if (pools[poolId].revenueHistory[i - 1].epochNumber <= startEpoch) {
                startIdx = i - 1;
                break;
            }
        }

        if (startIdx == pools[poolId].revenueHistory.length) {
            return new RevenueCheckpoint[](0) ; // No checkpoints found before startEpoch
        }

        uint256 endIdx = (startIdx >= count) ? startIdx - count + 1 : 0;
        RevenueCheckpoint[] memory checkpoints = new RevenueCheckpoint[](startIdx - endIdx + 1);

        for (uint256 i = startIdx; i >= endIdx && i < pools[poolId].revenueHistory.length; i--) {
            checkpoints[startIdx - i] = pools[poolId].revenueHistory[i];
        }

        return checkpoints;
    }

    // Public function to get stats about a specific pool
    function stats(uint256 poolId) public view returns (
        uint256 totalRevenue,
        uint256 totalClaimed,
        uint256 totalDeposited,
        uint256 totalUsers,
        uint256 unclaimedRevenue
    ) {
        totalRevenue = pools[poolId].totalRevenue;
        totalClaimed = pools[poolId].totalClaimed;
        totalDeposited = pools[poolId].totalDeposited;
        totalUsers = pools[poolId].users.length;
        unclaimedRevenue = totalRevenue - totalClaimed;
    }

    // Utility function to get the current epoch number
    function getCurrentEpoch() public view returns (uint256) {
        return block.number / 17280;
    }
}