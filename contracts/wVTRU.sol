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

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IPancakePair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract wVTRU is 
    Initializable, 
    ERC20Upgradeable,
    AccessControlUpgradeable, 
    ERC20BurnableUpgradeable, 
    UUPSUpgradeable {

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    uint public constant DECIMALS = 10 ** 18;

    uint public constant EPOCH_BLOCKS = 17280;
    uint public constant BASE_EPOCH_PERIOD = 720;
    uint public constant MINIMUM_WRAP_VTRU = 99e18; 

    bool private paused;
    address public pairAddress;

    uint public totalWrapped;
    uint public totalEpochWrapped;
    uint public totalEpochResetBlock;

    mapping(address => uint) private userWrappedLastBlock;
    mapping(uint => uint) public priceByEpoch;

    event Wrap(address indexed account, uint amount);
    event Unwrap(address indexed account, uint amount);

    function initialize() public initializer {
        __ERC20_init("Wrapped VTRU", "wVTRU");
        __ERC20Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(SERVICE_ROLE, msg.sender);

        paused = true;
        totalEpochResetBlock = epochNextBlock();
    }
/*
 circuitBreakerInfo →
(uint256): 110  WEI
(uint256): 11000  WEI
(uint256): 550  WEI
(uint256): 15709  WEI
(uint256): 137195  WEI
(uint256): 10202  WEI
*/
    function wrap() external payable whenNotPaused {
        require(msg.value >= MINIMUM_WRAP_VTRU, "Amount less than minimum wrap value");

        (, uint totalEpochWrapLimit, uint userWrapLimit, uint epochPeriod,,) = circuitBreakerInfo();

        if (msg.value > userWrapLimit * DECIMALS) {
            revert("Exceeds individual wrapping limit");
        }

        if (block.number < userWrappedLastBlock[msg.sender] + epochPeriod) {
            revert("Cannot wrap again within the same period");
        }

        if (block.number > totalEpochResetBlock) {
            priceByEpoch[epochCurrentBlock()] = priceCurrent(); // Approximation
            totalEpochResetBlock = epochNextBlock();
            totalEpochWrapped = 0;
        }

        if (msg.value + totalEpochWrapped > totalEpochWrapLimit * DECIMALS) {
            revert("Exceeds total epoch wrapping limit");
        }

        userWrappedLastBlock[msg.sender] = block.number;
        totalEpochWrapped += msg.value;

        _mint(msg.sender, msg.value);
        totalWrapped += msg.value;
    }

    function unwrapAll() external whenNotPaused {
        return unwrap(balanceOf(msg.sender));
    }

    function unwrap(uint amount) public whenNotPaused {
        require(amount > 0, "Must specify amount to unwrap");

        uint balance = balanceOf(msg.sender);
        require(balance >= amount, "Insufficient wVTRU balance");

        _burn(msg.sender, amount);
        totalWrapped -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer of VTRU failed");
    }

    function totals() public view returns(uint, uint, uint) {
        return (totalWrapped, totalEpochWrapped, totalEpochResetBlock);
    }

    function userInfo(address account) public view returns(uint, uint, uint) {
        (,,uint userWrapLimit, uint epochPeriod,,) = circuitBreakerInfo();
        return (userWrapLimit, userWrappedLastBlock[account], userWrappedLastBlock[account] + epochPeriod);
    }

    function priceCurrent() public view returns(uint) {
        IPancakePair pair = IPancakePair(pairAddress);

        // Get the reserves from the pair contract
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        uint wVTRUReserve = uint(reserve0);
        uint usdcReserve = uint(reserve1);

        require(wVTRUReserve > 0, "wVTRU reserve is zero");
        return ((usdcReserve * 1e18) / wVTRUReserve)  / 1e4;
    }
    
    function priceTrailing() public view returns(uint) {
        uint epoch = epochCurrentBlock() - EPOCH_BLOCKS;
        uint epochs = 0;
        uint total = 0;
        uint counter = 7;
        while (counter > 0) {
            counter--;
            if (priceByEpoch[epoch] > 0) {
                total += priceByEpoch[epoch];
                epochs++;
            }
            epoch -= EPOCH_BLOCKS;
        }
        return (total / epochs)  / 1e4;
    }

    function priceRange(uint startEpoch, uint endEpoch) public view returns(uint[] memory blockNumbers, uint[] memory prices) {
        require(endEpoch >= startEpoch, "End epoch can't be before Start epoch");
        blockNumbers = new uint[](endEpoch - startEpoch + 1);
        prices = new uint[](blockNumbers.length);
        for(uint e=startEpoch; e<endEpoch; e++) {
            uint epoch = e * EPOCH_BLOCKS;
            if (priceByEpoch[epoch] > 0) {
                blockNumbers[e - startEpoch] = epoch;
                prices[e - startEpoch] = priceByEpoch[epoch] / 1e4;
            }
        }
    }

    function circuitBreakerInfo() public view returns(uint, uint, uint, uint, uint, uint) {

        // Convert price to cents and round to nearest 10 cents
        uint currentPriceInCents = (priceCurrent()/10)  * 10;

        uint totalEpochWrapLimit = currentPriceInCents * 100 ; // Adjust for 18 decimals
        uint userWrapLimit = totalEpochWrapLimit / 20;
        uint epochPeriod = (BASE_EPOCH_PERIOD * 2400) / currentPriceInCents; // Calculate epoch period in blocks
        epochPeriod = epochPeriod < BASE_EPOCH_PERIOD ? BASE_EPOCH_PERIOD : (epochPeriod > EPOCH_BLOCKS ? EPOCH_BLOCKS : epochPeriod); // Constrain between BASE_EPOCH_PERIOD and EPOCH_BLOCKS

        return (
                    currentPriceInCents, 
                    totalEpochWrapLimit,  
                    userWrapLimit, 
                    epochPeriod,
                    totalWrapped / DECIMALS,
                    totalEpochWrapped / DECIMALS
                );
    }

    function epochCurrentBlock() public view returns (uint) {
        return (epochCurrent() * EPOCH_BLOCKS);
    }

    function epochNextBlock() public view returns (uint) {
        return (epochCurrentBlock()+EPOCH_BLOCKS);
    }

    function epochCurrent() public view returns (uint) {
        return block.number / EPOCH_BLOCKS;
    }

    function epochNext() public view returns (uint) {
        return epochCurrent()+1;
    }
    
    function setPairAddress(address newPairAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        pairAddress = newPairAddress;
    }

    function mintAdmin() public payable onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(msg.sender, msg.value);
        totalWrapped += msg.value;
    }

    receive() external payable {
    }

    function recoverVTRU() external onlyRole(DEFAULT_ADMIN_ROLE) {
        recoverVTRU(address(this).balance);
    }

    function recoverVTRU(uint amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool recovered, ) = payable(msg.sender).call{value: amount}("");
        require(recovered, "Recovery failed"); 
    }

    // Pause the contract
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = true;
    }

    // Unpause the contract
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = false;
    }

    modifier whenNotPaused() {
        require(paused == false || hasRole(SERVICE_ROLE, msg.sender), "Contract is paused");
        _;
    }

    function resetUserPeriod(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        delete userWrappedLastBlock[account];
    }

    // Authorize contract upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // Check supported interfaces
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
