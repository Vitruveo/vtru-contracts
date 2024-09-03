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

contract CollectorCredit is
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
    CountersUpgradeable.Counter private _creditClassId;
    CountersUpgradeable.Counter private _tokenId;

    uint public constant DECIMALS = 10 ** 18;
    uint public constant INACTIVE_CREDIT_BLOCK = 50000000;

    /****************************************************************************/
    /*                                  ROLES                                   */
    /****************************************************************************/
    bytes32 public constant GRANTER_ROLE = bytes32(uint256(0x01));
    bytes32 public constant UPGRADER_ROLE = bytes32(uint256(0x02));
    bytes32 public constant REEDEEMER_ROLE = bytes32(uint256(0x03));
    bytes32 public constant BLOCKER_ROLE = bytes32(uint256(0x04));

    /****************************************************************************/
    /*                                 TOKENS                                   */
    /****************************************************************************/

    struct CreditNFTClass {
        uint256 id;
        string  name; 
        bool isUSD;
        uint256 value;
    }

    struct CreditNFT {
        uint256 id;
        uint256 classId;
        bool isUSD;
        uint256 value;  
        uint256 activeBlock;
    }

    struct GlobalData {
        string classImageURI;
        
        mapping(uint256 => CreditNFT) CreditNFTs;
        mapping(uint256 => CreditNFTClass) CreditNFTClasses;
        mapping(address => uint256[]) CreditNFTsByOwner;
        mapping(uint256 => uint256) TotalNFTsByClass;
    }
    
    GlobalData public global;
    uint256 public usdRedeemed;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;
    bool private _blockTransfers;

    mapping(address => bool) BlockedAccounts;
    mapping(address => bool) BlockedVaults;
    mapping(uint => bool) BurnList;

    event CollectorCreditGranted(uint256 indexed tokenId, address indexed account, bool isUSD, uint256 value);
    event CollectorCreditRedeemed(address indexed account, uint64 amountCents, uint256 licenseInstanceId, uint64 redeemedCents, uint256 vtru, address vault);

    function initialize() public initializer {
        __ERC721_init("Vitruveo Collector Credit", "VCOLC");
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(GRANTER_ROLE, msg.sender);
        _grantRole(REEDEEMER_ROLE, msg.sender);
        initClasses();
    }

    function version() public pure returns(string memory) {
        return "0.5.0";
    }

    function initClasses() internal {
        global.classImageURI = "https://nftstorage.link/ipfs/bafybeicjca46w5djtghbdbjuv2up4diftcu4abm52kv2my3mmtslzmnnju/";
        registerCreditClass(1, "USD10", true, 10);
    }

    // function grantCreditNFT(
    //     uint256 classId,
    //     address account,
    //     uint256 activeBlock,
    //     uint256 quantity
    // ) public onlyRole(GRANTER_ROLE) whenNotPaused {
        
    //     require(BlockedAccounts[account] == false, "Account is blocked");

    //     CreditNFTClass memory creditNFTClass = global.CreditNFTClasses[classId];

    //     require(
    //         creditNFTClass.value > 0, 
    //         "Specified token class not active."
    //     );

    //     for(uint256 i=0;i<quantity;i++) {
    //         _tokenId.increment();

    //         CreditNFT storage newCreditNFT = global.CreditNFTs[_tokenId.current()];
    //         newCreditNFT.id = _tokenId.current();
    //         newCreditNFT.classId = classId;
    //         newCreditNFT.isUSD = creditNFTClass.isUSD;
    //         newCreditNFT.value = creditNFTClass.value;
    //         newCreditNFT.activeBlock = activeBlock == 0 ? block.number : activeBlock;

    //         addTokenToOwner(newCreditNFT.id, account);
    //         global.TotalNFTsByClass[classId]++;

    //         _mint(account, newCreditNFT.id);

    //         emit CollectorCreditGranted(newCreditNFT.id, account, newCreditNFT.isUSD, newCreditNFT.value);
    //     }
    // }

    // function redeemUsd(address account, uint256 licenseInstanceId, address[2] memory payees, uint64[2] memory paymentCents, uint256 usdVtruExchangeRate) onlyRole(REEDEEMER_ROLE) public whenNotPaused nonReentrant returns(uint64 redeemedCents) {

    //     require(BlockedAccounts[account] == false, "Account is blocked");
    //     require(BlockedVaults[payees[0]] == false, "Vault is blocked");
    //     require(payees[0] != address(0) && payees[1] != address(0), "One or more payee addresses not set");

    //     uint256[] memory nfts = global.CreditNFTsByOwner[account];
    //     for(uint f=0; f<nfts.length; f++) {
    //         if (global.CreditNFTs[nfts[f]].activeBlock < INACTIVE_CREDIT_BLOCK) {
    //             redeemedCents += uint64(global.CreditNFTs[nfts[f]].value) * 100;
    //             removeTokenFromOwner(global.CreditNFTs[nfts[f]].id, account);
    //             global.TotalNFTsByClass[global.CreditNFTs[nfts[f]].classId]--;
    //             global.CreditNFTs[nfts[f]].activeBlock = INACTIVE_CREDIT_BLOCK; // Burn later
    //             delete global.CreditNFTs[nfts[f]];
    // //            _burn(tokenId);      
                
    //             if (redeemedCents >= paymentCents[0] + paymentCents[1]) {
    //                 break;
    //             }
    //         }
    //     }

    //     require(redeemedCents >= paymentCents[0] + paymentCents[1], "Insufficient credits");

    //     uint256[2] memory vtru = [
    //         (paymentCents[1] * DECIMALS) / usdVtruExchangeRate, //platform fee vtru
    //         ((redeemedCents - paymentCents[1]) * DECIMALS) / usdVtruExchangeRate  //creator vtru
    //     ];

    //     require(address(this).balance >= vtru[0] + vtru[1], "Insufficient Collector Credit VTRU balance");

    //     (bool fees, ) = payable(payees[1]).call{value: vtru[0]}("");
    //     require(fees, "Fee payout failed");

    //     (bool payout, ) = payable(payees[0]).call{value: vtru[1]}(""); // Payout to creator (all remaining funds)
    //     require(payout, "Asset payout failed");  

    //     emit CollectorCreditRedeemed(account, paymentCents[0] + paymentCents[1], licenseInstanceId, redeemedCents, vtru[0] + vtru[1], payees[0]);
    // }


    // function removeTokenFromOwner(uint256 tokenId, address account) internal {
    //     for(uint256 n=0;n<global.CreditNFTsByOwner[account].length;n++) {
    //         if (global.CreditNFTsByOwner[account][n] == tokenId) {
    //             global.CreditNFTsByOwner[account][n] = global.CreditNFTsByOwner[account][global.CreditNFTsByOwner[account].length-1];
    //             global.CreditNFTsByOwner[account].pop();
    //             break;
    //         }
    //     }        
    // }

    // function addTokenToOwner(uint256 tokenId, address account) internal {
    //     global.CreditNFTsByOwner[account].push(tokenId); 
    // }

    // function activateTokens(uint[] memory tokens) public onlyRole(GRANTER_ROLE) {
    //     for(uint f=0; f<tokens.length; f++) {
    //         global.CreditNFTs[tokens[f]].activeBlock = block.number;
    //     }
    // }

    function getAccountTokens(address account) public view returns(CreditNFT[] memory){

        uint256[] memory nfts = global.CreditNFTsByOwner[account];
        CreditNFT[] memory creditNFTs = new CreditNFT[](nfts.length);
        for(uint f=0; f<nfts.length; f++) {
            creditNFTs[f] = global.CreditNFTs[nfts[f]];
        }
        return creditNFTs;
    }

    function burn(uint start, uint finish) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        uint[] memory ids = new uint[](finish-start+1);
        address[] memory owners = new address[](finish-start+1);
        for(uint i=start; i<finish; i++) {
            delete global.CreditNFTs[i];
            if (_ownerOf(i) != address(0x00)) {
                _burn(i);
            }
        }
    }

    // function getTokenOwners(uint start, uint finish) public view returns(uint[] memory, address[] memory) {
    //     uint[] memory ids = new uint[](finish-start+1);
    //     address[] memory owners = new address[](finish-start+1);
    //     for(uint i=start; i<finish; i++) {
    //         if(global.CreditNFTs[i].id > 0 ) {
    //             owners[i - start] = _ownerOf(i);
    //             ids[i - start] = i;
    //         }
    //     }
    //     return (ids, owners);
    // }

    function getAvailableCredits(address account) public view returns(uint tokens, uint creditCents, uint creditOther) {
        uint256[] memory nfts = global.CreditNFTsByOwner[account];
        for(uint f=0; f<nfts.length; f++) {
            if (global.CreditNFTs[nfts[f]].activeBlock < INACTIVE_CREDIT_BLOCK) {
                creditCents += global.CreditNFTs[nfts[f]].value * 100;
                tokens++;
            }
        }  
    }

    function getCreditTokenInfo(uint256 id) public view  returns (CreditNFT memory)
    {
        return global.CreditNFTs[id];
    }

    function getCreditClassInfo(uint256 id) public view  returns (CreditNFTClass memory)
    {
        return global.CreditNFTClasses[id];
    }

    function tokenURI(uint256 tokenId) override public view returns (string memory){

        CreditNFT memory creditNFT = global.CreditNFTs[tokenId];    
        require(creditNFT.classId > 0, "Token ID does not exist");

        CreditNFTClass memory creditNFTClass = global.CreditNFTClasses[creditNFT.classId];

	    string memory json = Base64Upgradeable.encode(bytes(string(abi.encodePacked('{"name": "', creditNFTClass.name, '", "description": "Vitruveo Collector Credit NFT", "image": "', global.classImageURI, creditNFTClass.name, '.png"}'))));
	
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    // function transferFrom(address from, address to, uint256 tokenId) public override {
    //     require(!_blockTransfers, "Transfers not allowed");
    //     require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
        
    //     removeTokenFromOwner(tokenId, from);
    //     addTokenToOwner(tokenId, to);
    //     _transfer(from, to, tokenId);
    // }

    // function safeTransferFrom(address from, address to, uint256 tokenId) public override {
    //     safeTransferFrom(from, to, tokenId, "");
    // }

    // function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
    //     require(!_blockTransfers, "Transfers not allowed");
    //     require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
    //     removeTokenFromOwner(tokenId, from);
    //     addTokenToOwner(tokenId, to);
    //     _safeTransfer(from, to, tokenId, data);
    // }

    function currentSupply() public view returns (uint256) {
        return _tokenId.current();
    }

    // Registers a Credit NFT Class
    function registerCreditClass(
        uint256 id,
        string memory name,
        bool isUSD,
        uint256 value
    ) public onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused returns (CreditNFTClass memory) {

        global.CreditNFTClasses[id] = CreditNFTClass(id, name, isUSD, value);
  
        return global.CreditNFTClasses[id];
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

    function blockAccount(address account) public  onlyBlocker() {
        BlockedAccounts[account] = true;
    }

    function unblockAccount(address account) public onlyBlocker() {
        delete BlockedAccounts[account];
    }

    function blockVault(address vault) public  onlyBlocker() {
        BlockedVaults[vault] = true;
    }

    function unblockVault(address vault) public onlyBlocker() {
        delete BlockedVaults[vault];
    }

    function blockTransfers(bool setting) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _blockTransfers = setting;
    }

    function accountBlockStatus(address account) public view returns(bool) {
        return BlockedAccounts[account] ;
    }

    function vaultBlockStatus(address vault) public view returns(bool) {
        return BlockedVaults[vault] ;
    }

    function transferBlockStatus() public view returns(bool) {
        return _blockTransfers;
    }

    function recoverVTRU() external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool recovered, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(recovered, "Recovery failed"); 
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

        modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }

    modifier onlyBlocker() {
        require(hasRole(BLOCKER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorized user");
        _;
    }
}

