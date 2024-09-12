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
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint vusdAmount) external returns (bool);
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint vusdAmount) external returns (bool);
}

interface IWVTRU {
    function priceCurrent() external view returns (uint);
}

interface ICreatorVault {
    function isVaultWallet(address) external returns(bool);
}

contract VUSD is Initializable, ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address payable;

    bytes32 public constant GRANTER_ROLE = keccak256("GRANTER_ROLE");
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");
    bytes32 public constant BLOCKER_ROLE = keccak256("BLOCKER_ROLE");

    address public constant USDC_ADDRESS  = 0xbCfB3FCa16b12C7756CD6C24f1cC0AC0E38569CF;
    address public constant WVTRU_ADDRESS = 0x3ccc3F22462cAe34766820894D04a40381201ef9;

    uint public constant BLOCKS_PER_EPOCH = 17280;
    uint public constant VTRU_DECIMALS = 10 ** 18;
    uint public constant VUSD_DECIMALS = 10 ** 6;

    struct GrantInfo {
        uint amount;
        uint balance;
        uint endEpoch;
    }

    mapping(address => GrantInfo) private grants;
    mapping(address => mapping(address => uint)) private redemptionAmounts;
    mapping(address => mapping(address => uint)) private redemptionCounts;

    uint public maxRedemptionAmountPerVault;
    uint public maxRedemptionsPerVault;

    event Granted(address indexed to, uint vusdAmount);
    event Revoked(address indexed account);
    event Redeemed(address indexed account, uint indexed licenseInstanceId, address[5] indexed payees, uint[5] cents);

    function initialize() public initializer {
        __ERC20_init("Vitruveo Stablecoin", "VUSD");
        __Ownable_init();
        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GRANTER_ROLE, msg.sender);
        _setupRole(REDEEMER_ROLE, msg.sender);

        maxRedemptionAmountPerVault = 1000 * VUSD_DECIMALS;
        maxRedemptionsPerVault = 5; 
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @dev Mint VUSD by paying with USDC
    function mintWithUsdc(address to, uint vusdAmount) public whenNotPaused nonReentrant {
        IERC20 usdc = IERC20(USDC_ADDRESS);
        require(usdc.transferFrom(msg.sender, address(this), vusdAmount), "USDC transfer failed");

        _mint(to, vusdAmount);
    }

    /// @dev Mint VUSD to a specified address by paying with VTRU
    function mintWithVtru(address to, uint vusdAmount) public payable whenNotPaused nonReentrant {
        uint vtruRequired = getVtruConversion(vusdAmount);
        require(msg.value >= vtruRequired, "Insufficient VTRU sent");

        _mint(to, vusdAmount);

        // Refund any excess VTRU sent
        if (msg.value > vtruRequired) {
            payable(msg.sender).sendValue(msg.value - vtruRequired);
        }
    }

    /// @dev Calculate the required vusdAmount of VTRU for a given vusdAmount of VUSD
    function getVtruConversion(uint vusdAmount) public view returns (uint) {
        uint price = getCurrentVtruPrice();
        return (vusdAmount * 100 * VTRU_DECIMALS) / (price * VUSD_DECIMALS);
    }

    /// @dev Calculate the required vusdAmount of VUSD for a given vusdAmount of VTRU
    function getVusdConversion(uint vtruAmount) public view returns (uint) {
        uint price = getCurrentVtruPrice();
        return (vtruAmount * price * VUSD_DECIMALS) / (100 * VTRU_DECIMALS);
    }

    /// @dev Get the current price of VTRU in cents, returns 100 if the price is zero
    function getCurrentVtruPrice() public view returns (uint) {
        if (fallbackVtruPrice > 0) {
            return fallbackVtruPrice;
        } else {
            return IWVTRU(WVTRU_ADDRESS).priceCurrent();
        }
    }

    /// @dev Grant tokens to a specified address by paying with VTRU
    function grant(address to, uint cents, uint epochs) public payable whenNotPaused nonReentrant onlyRole(GRANTER_ROLE) {
        require(blockList[to] == false, "Recipient is blocked");

        uint vusdAmount = (cents * VUSD_DECIMALS) / 100;
        uint vtruRequired = getVtruConversion(vusdAmount);
        require(msg.value >= vtruRequired, "Insufficient VTRU sent");

        uint currentEpoch = block.number / BLOCKS_PER_EPOCH;
        uint endEpoch = currentEpoch + epochs;

        grants[to] = GrantInfo({
            amount: grants[to].amount + vusdAmount,
            balance: grants[to].balance + vusdAmount,
            endEpoch: endEpoch
        });

        _mint(address(to), vusdAmount); // Mint to the contract address as escrow

        // Refund any excess VTRU sent
        if (msg.value > vtruRequired) {
            payable(msg.sender).sendValue(msg.value - vtruRequired);
        }

        emit Granted(to, vusdAmount);
    }

    function revoke(address account) public onlyRole(GRANTER_ROLE) {
        delete grants[account];
        emit Revoked(account);
    }

    function getGrant(address grantee) public view returns(GrantInfo memory) {
        return grants[grantee];
    }

    /// @dev Get the grant balance of an account
    function grantBalanceOf(address account) public view returns (uint) {
        uint currentEpoch = block.number / BLOCKS_PER_EPOCH;
        if (currentEpoch > grants[account].endEpoch) {
            return 0;
        }
        return grants[account].balance;
    }

    function nonGrantBalanceOf(address account) public view returns (uint) {
        return balanceOf(account) - grantBalanceOf(account);
    }

    function getMaxVaultRedemptionLimitInCents(address vault) public view returns(uint) {
        uint vaultLimit = maxRedemptionAmountPerVault;
        if (vaultMaxRedemptionAmounts[vault] > 0) {
            vaultLimit = vaultMaxRedemptionAmounts[vault]; // Individual Vault limits could be higher or lower
        }
        return vaultLimit / 1e4;
    }

    function getAccountVaultInfo(address account, address vault) public view returns(uint limitCents, uint redeemedCents, uint limitCount, uint redeemedCount) {
        uint max = getMaxVaultRedemptionLimitInCents(vault);
        uint used = redemptionAmounts[account][vault] / 1e4;
        return (
            max, 
            used,
            maxRedemptionsPerVault,
            redemptionCounts[account][vault]
        );
    }

    function getBalancesInCents(address account) public view returns(uint, uint) {
        uint grantCents = grantBalanceOf(account) / 1e4;
        uint nonGrantCents = nonGrantBalanceOf(account) / 1e4;
        return (grantCents, nonGrantCents);
    }
    
    // function balanceOf(address owner) public view virtual override returns (uint256) {
    //     require(owner != address(0), "ERC721: address zero is not a valid owner");
    //     return _balances[owner];
    // }

    function calculateRedemptionAmounts(address account, address[5] memory payees, uint[5] memory cents) public view returns(uint totalVusd, uint grantVusd, uint nonGrantVusd, uint balanceVusd) {
        // Calculate aggregate cents and VUSD
        uint totalCents;
        for(uint c=0;c<payees.length;c++) {
            if ((cents[c] > 0) && (blockList[payees[c]] == false)) {
                totalCents += cents[c];
                totalVusd += (cents[c] * VUSD_DECIMALS) / 100;
            }
        } 

        // Get user balances
        (uint grantCents, uint nonGrantCents) = getBalancesInCents(account);

        address vault = payees[0]; // Vault is always first address

        // First use up whatever grant amount is possible
        if ((grantCents > 0) && (redemptionCounts[account][vault] < maxRedemptionsPerVault)) {

            uint vaultLimit = maxRedemptionAmountPerVault;
            if (vaultMaxRedemptionAmounts[vault] > 0) {
                vaultLimit = vaultMaxRedemptionAmounts[vault]; // Individual Vault limits could be higher or lower
            }

            grantVusd = grantCents * 1e4;

            uint limitVusd = totalVusd > vaultLimit ? vaultLimit : totalVusd;

            if (grantVusd >= limitVusd) {
                grantVusd = limitVusd;
            }
        }

        balanceVusd = totalVusd - grantVusd;

        if (balanceVusd > 0) {
            nonGrantVusd = nonGrantCents * 1e4;

            if (nonGrantVusd >= balanceVusd) {
                nonGrantVusd = balanceVusd;
                balanceVusd = 0;
            } else {
                balanceVusd = balanceVusd - nonGrantVusd;
            }
        }
    } 

    /// @dev Redeem tokens on behalf of a user and pay payees
    function redeem(address account, uint licenseInstanceId, address[5] memory payees, uint[5] memory cents) public whenNotPaused nonReentrant onlyRole(REDEEMER_ROLE) {
        (uint totalVusd, uint grantVusd, , uint balanceVusd) = calculateRedemptionAmounts(account, payees, cents);

        if (totalVusd > 0) {
            require(balanceVusd == 0, "Insufficient funds");
    
            // Check if contract has funds
            require(address(this).balance >= getVtruConversion(totalVusd), "Insufficient collateral");

            if (grantVusd > 0) {
                address vault = payees[0]; // Vault is always first address
                require(ICreatorVault(vault).isVaultWallet(account) == false, "Cannot redeem for own work");
                redemptionAmounts[account][vault] += grantVusd;
                redemptionCounts[account][vault]++;
                grants[account].balance -= grantVusd;
            }

            _burn(address(account), totalVusd);

            for(uint p=0;p<payees.length;p++) {
                if (cents[p] > 0) {
                    payable(payees[p]).sendValue(getVtruConversion((cents[p] * VUSD_DECIMALS)/100)); // Fails if no collateral
                }
            }

            emit Redeemed(account, licenseInstanceId, payees, cents);
        }
    }

    /// @dev Pause token transfers
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @dev Unpause token transfers
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @dev Hook that is called before any transfer of tokens
    /// Prevents transfer of granted tokens
    function _beforeTokenTransfer(address from, address to, uint vusdAmount) internal override whenNotPaused {
        if (from != address(0) && to != address(0)) {
            require(blockList[from] == false, "Sender is blocked");
            require(blockList[to] == false, "Recipient is blocked");
            require(balanceOf(from) - grants[from].balance >= vusdAmount, "Transfer amount exceeds available non-grant balance");
        }
        super._beforeTokenTransfer(from, to, vusdAmount);
    }

    /// @dev Set the maximum redemption vusdAmount per vault
    function setDefaultVaultMaxRedemptionAmount(uint vusdAmount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        maxRedemptionAmountPerVault = vusdAmount;
    }

    /// @dev Set the maximum number of redemptions per vault
    function setDefaultVaultMaxRedemptionCount(uint count) public onlyRole(DEFAULT_ADMIN_ROLE) {
        maxRedemptionsPerVault = count;
    }


    /// @dev Withdraw all USDC from the contract
    function withdrawUsdc() public onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint balance = usdc.balanceOf(address(this));
        require(balance > 0, "No USDC balance to withdraw");
        usdc.transfer(msg.sender, balance);
    }

    /// @dev Shortcut to buying VUSD with VTRU
    receive() external payable {

        uint vusdAmount = getVusdConversion(msg.value);
        if (vusdAmount > 0) {
            require(blockList[msg.sender] == false, "Requester is blocked");
            _mint(msg.sender, vusdAmount);
        }
    }

    /// @dev Withdraw VTRU from the contract
    function withdrawVtru() public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint balance = address(this).balance;
        uint collateralBalance = (balance * 150) / 100; // 150% collateral balance
        uint amountToWithdraw = (balance * 95) / 100; // 95% of the contract balance

        require(balance >= collateralBalance, "Insufficient VTRU for collateral requirement");
        payable(msg.sender).sendValue(amountToWithdraw);
    }

    function depositCollateral() public payable {}

    /// @dev Check the collateralization ratio in basis points
    function collateralRatio() public view returns (uint ratio) {
        uint price = getCurrentVtruPrice();
        uint vtruValueInCents = (address(this).balance * price) / (100 * VTRU_DECIMALS);
        ratio = (vtruValueInCents * VUSD_DECIMALS * 10000) / totalSupply();
    }

    // Block List
    mapping(address => bool) private blockList;

    function addBlock(address account) public onlyRole(BLOCKER_ROLE) {
        blockList[account] = true;
    }

    function removeBlock(address account) public onlyRole(BLOCKER_ROLE) {
        delete blockList[account];
    }

    mapping(address => uint) private vaultMaxRedemptionAmounts;
    function setMaxRedemptionAmountByVault(uint dollars, address vault) public onlyRole(BLOCKER_ROLE) {
        vaultMaxRedemptionAmounts[vault] = dollars * VUSD_DECIMALS;
    }

    uint public fallbackVtruPrice;

    /// @dev Fallback VTRU price for testnet
    function setFallbackVtruPrice(uint cents) public onlyRole(DEFAULT_ADMIN_ROLE) {
        fallbackVtruPrice = cents;
    }

}
