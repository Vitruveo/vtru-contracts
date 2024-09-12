// SPDX-License-Identifier: MIT
// (c)2021-2024 Atlas
// security-contact: atlas@vialabs.io

pragma solidity ^0.8.9;

interface IERC20cl {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface IMessageV3 {
    event SendRequested(uint txId, address sender, address recipient, uint chain, bool express, bytes data, uint16 confirmations);
    event SendProcessed(uint txId, uint sourceChainId, address sender, address recipient);
    event Success(uint txId, uint sourceChainId, address sender, address recipient, uint amount);
    event ErrorLog(uint txId, string message);
    event SetExsig(address caller, address signer);
    event SetMaxgas(address caller, uint maxGas);
    event SetMaxfee(address caller, uint maxFee);

    function chainsig() external view returns (address signer);
    function weth() external view returns (address wethTokenAddress);
    function feeToken() external view returns (address feeToken);
    function feeTokenDecimals() external view returns (uint feeTokenDecimals);
    function minFee() external view returns (uint minFee);
    function bridgeEnabled() external view returns (bool bridgeEnabled);
    function takeFeesOffline() external view returns (bool takeFeesOffline);
    function whitelistOnly() external view returns (bool whitelistOnly);

    function enabledChains(uint destChainId) external view returns (bool enabled);
    function customSourceFee(address caller) external view returns (uint customSourceFee);
    function maxgas(address caller) external view returns (uint maxgas);
    function exsig(address caller) external view returns (address signer);

    // @dev backwards compat with BridgeClient
    function minTokenForChain(uint chainId) external returns (uint amount);

    function sendMessage(address recipient, uint chain, bytes calldata data, uint16 confirmations, bool express) external returns (uint txId);
    // @dev backwards compat with BridgeClient
    function sendRequest(address recipient, uint chainId, uint amount, address referrer, bytes calldata data, uint16 confirmations) external returns (uint txId);

    function setExsig(address signer) external;
    function setMaxgas(uint maxgas) external;
    function setMaxfee(uint maxfee) external;

    function getSourceFee(uint _destChainId, bool _express) external view returns (uint _fee);
}

interface IFeature {
    function getPayload(uint _txId) external view returns (bytes memory);
}

interface IFeatureGateway {
    function isFeatureEnabled(uint32) external view returns (bool);
    function featureAddresses(uint32) external view returns (address);
    function messageV3() external view returns (IMessageV3);
    function processForward(uint _txId, uint _sourceChainId, uint _destChainId, address _sender, address _recipient, uint _gas, bytes[] calldata _data) external;
    function process(uint txId, uint sourceChainId, uint destChainId, address sender, address recipient, uint gas, uint32 featureId, bytes calldata featureReply, bytes[] calldata data) external;
}

/**
 * @title MessageV3 Client
 * @author Atlas <atlas@vialabs.io>
 */
abstract contract MessageClient {
    IMessageV3 public MESSAGEv3;
    IERC20cl public FEE_TOKEN;
    IFeatureGateway public FEATURE_GATEWAY;
    mapping(uint => mapping(uint32 => ChainData)) public FEATURES;

    struct ChainData {
        address endpoint; // address of this contract on specified chain
        bytes endpointExtended; // address of this contract on non EVM
        uint16 confirmations; // source confirmations
        bool extended; // are we using extended endpoint? (addresses larger than uint256)
    }
    mapping(uint => ChainData) public CHAINS;
    address public MESSAGE_OWNER;

    modifier onlySelf(address _sender, uint _sourceChainId) {
        require(msg.sender == address(MESSAGEv3), "MessageClient: not authorized");
        require(_sender == CHAINS[_sourceChainId].endpoint, "MessageClient: not authorized");
        _;
    }

    modifier onlyActiveChain(uint _destinationChainId) {
        require(CHAINS[_destinationChainId].endpoint != address(0), "MessageClient: destination chain not active");
        _;
    }

    modifier onlyMessageOwner() {
        require(msg.sender == MESSAGE_OWNER, "MessageClient: not authorized");
        _;
    }

    event MessageOwnershipTransferred(address previousOwner, address newOwner);
    event RecoverToken(address owner, address token, uint amount);
    event SetMaxgas(address owner, uint maxGas);
    event SetMaxfee(address owner, uint maxfee);
    event SetExsig(address owner, address exsig);
    event SendMessageWithFeature(uint txId, uint destinationChainId, uint32 featureId, bytes featureData);

    function __MessageClient_init() internal {
        MESSAGE_OWNER = msg.sender;
    }

    function transferMessageOwnership(address _newMessageOwner) external onlyMessageOwner {
        MESSAGE_OWNER = _newMessageOwner;
        emit MessageOwnershipTransferred(msg.sender, _newMessageOwner);
    }

    /** BRIDGE RECEIVER */
    // @dev DEPRICATED kept for backwards compatibility
    function messageProcess(
        uint _txId,          // transaction id
        uint _sourceChainId, // source chain id
        address _sender,     // corresponding MessageClient address on source chain
        address,
        uint,
        bytes calldata _data // encoded message from source chain
    ) external virtual onlySelf (_sender, _sourceChainId) {
        _processMessage(_txId, _sourceChainId, _data);
    }

    // @dev PREFERRED if no Features used
    // this is extended by the implementing class if not using Features
    function _processMessage(uint _txId, uint _sourceChainId, bytes calldata _data) internal virtual {
        (uint32 _featureId, bytes memory _featureData, bytes memory _messageData) = abi.decode(_data, (uint32, bytes, bytes));
        
        // call the implementing class to process the message
        _processMessageWithFeature(_txId, _sourceChainId, _messageData, _featureId, _featureData, _getFeatureResponse(_featureId, _txId));
    }

    // @dev REQUIRED if using Features
    // this is extended by the implementing class if using Features
    function _processMessageWithFeature(
        uint,         // transaction id
        uint,         // source chain id
        bytes memory, // encoded message from source chain
        uint32,       // feature id
        bytes memory, // encoded feature data
        bytes memory  // reply from feature processing off-chain
    ) internal virtual {
        revert("MessageClient: _processMessage or _processMessageWithFeature not implemented");
    }

    function _getFeatureResponse(uint32 _featureId, uint _txId) internal view returns (bytes memory) {
        return IFeature(FEATURE_GATEWAY.featureAddresses(_featureId)).getPayload(_txId);
    }
    
    /** BRIDGE SENDER */
    function _sendMessage(uint _destinationChainId, bytes memory _data) internal returns (uint _txId) {
        ChainData memory _chain = CHAINS[_destinationChainId];
        if(_chain.extended) { // non-evm addresses larger than uint256
            _data = abi.encode(_data, _chain.endpointExtended);
        }
        return IMessageV3(MESSAGEv3).sendMessage(
            _chain.endpoint,      // corresponding MessageClient contract address on destination chain
            _destinationChainId,  // id of the destination chain
            _data,                // arbitrary data package to send
            _chain.confirmations, // amount of required transaction confirmations
            false                 // send express mode on destination
        );
    }

    function _sendMessageExpress(uint _destinationChainId, bytes memory _data) internal returns (uint _txId) {
        ChainData memory _chain = CHAINS[_destinationChainId];
        if(_chain.extended) { // non-evm addresses larger than uint256
            _data = abi.encode(_data, _chain.endpointExtended);
        }
        return IMessageV3(MESSAGEv3).sendMessage(
            _chain.endpoint,      // corresponding MessageV3Client contract address on destination chain
            _destinationChainId,  // id of the destination chain
            _data,                // arbitrary data package to send
            _chain.confirmations, // amount of required transaction confirmations
            true                  // send express mode on destination
        );
    }

    function _sendMessageWithFeature(uint _destinationChainId, bytes memory _messageData, uint32 _featureId, bytes memory _featureData) internal returns (uint _txId) {
        require(FEATURE_GATEWAY.isFeatureEnabled(_featureId), "MessageClient: feature not enabled");

        // wrap feature data into message data so it can be signed
        bytes memory _data = abi.encode(_featureId, _featureData, _messageData);

        ChainData memory _chain = CHAINS[_destinationChainId];
        if(_chain.extended) { // non-evm addresses larger than uint256
            _data = abi.encode(_data, _chain.endpointExtended);
        }

        _txId = IMessageV3(MESSAGEv3).sendMessage(
            _chain.endpoint,      // corresponding MessageV3Client contract address on destination chain
            _destinationChainId,  // id of the destination chain
            _data,                // arbitrary data package to send
            _chain.confirmations, // amount of required transaction confirmations
            false                 // send express mode on destination
        );

        // signal we have feature data included with the message data
        emit SendMessageWithFeature(_txId, _destinationChainId, _featureId, _featureData);
    }

    /** OWNER */
    function configureClientExtended(
        address _messageV3, // MessageV3 bridge address
        uint[] calldata _chains, // list of chains to accept as valid destinations
        bytes[] calldata _endpoints, // list of corresponding MessageV3Client addresses on each chain
        uint16[] calldata _confirmations // confirmations required on each chain before processing
    ) external onlyMessageOwner {
        uint _chainsLength = _chains.length;
        for(uint x=0; x < _chainsLength; x++) {
            CHAINS[_chains[x]].confirmations = _confirmations[x];
            CHAINS[_chains[x]].endpointExtended = _endpoints[x];
            CHAINS[_chains[x]].extended = true;
            CHAINS[_chains[x]].endpoint = address(1);
        }

        _configureMessageV3(_messageV3);
    }

    function configureClient(
        address _messageV3, // MessageV3 bridge address
        uint[] calldata _chains, // list of chains to accept as valid destinations
        address[] calldata _endpoints, // list of corresponding MessageV3Client addresses on each chain
        uint16[] calldata _confirmations // confirmations required on each chain before processing
    ) public onlyMessageOwner {
        uint _chainsLength = _chains.length;
        for(uint x=0; x < _chainsLength; x++) {
            CHAINS[_chains[x]].confirmations = _confirmations[x];
            CHAINS[_chains[x]].endpoint = _endpoints[x];
            CHAINS[_chains[x]].extended = false;
        }

        _configureMessageV3(_messageV3);
    }

    function configureFeatureGateway(address _featureGateway) external onlyMessageOwner {
        FEATURE_GATEWAY = IFeatureGateway(_featureGateway);
    }

    function _configureMessageV3(address _messageV3) internal {
        MESSAGEv3 = IMessageV3(_messageV3);
        FEE_TOKEN = IERC20cl(MESSAGEv3.feeToken());

        // approve bridge for source chain fees (limited per transaction with setMaxfee)
        if(address(FEE_TOKEN) != address(0)) {
            FEE_TOKEN.approve(address(MESSAGEv3), type(uint).max);
        }

        // approve bridge for destination gas fees (limited per transaction with setMaxgas)
        if(address(MESSAGEv3.weth()) != address(0)) {
            IERC20cl(MESSAGEv3.weth()).approve(address(MESSAGEv3), type(uint).max);
        }
    }

    function setExsig(address _signer) public onlyMessageOwner {
        MESSAGEv3.setExsig(_signer);
        emit SetExsig(msg.sender, _signer);
    }

    function setMaxgas(uint _maxGas) public onlyMessageOwner {
        MESSAGEv3.setMaxgas(_maxGas);
        emit SetMaxgas(msg.sender, _maxGas);
    }

    function setMaxfee(uint _maxFee) public onlyMessageOwner {
        MESSAGEv3.setMaxfee(_maxFee);
        emit SetMaxfee(msg.sender, _maxFee);
    }

    function recoverToken(address _token, uint _amount) public onlyMessageOwner {
        if(_token == address(0)) {
            // payable(msg.sender).transfer(_amount);
            // @note Zk needs
            (bool success, ) = payable(msg.sender).call{value: _amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20cl(_token).transfer(msg.sender, _amount);
        }
        emit RecoverToken(msg.sender, _token, _amount);
    }

    function isSelf(address _sender, uint _sourceChainId) public view returns (bool) {
        if(_sender == CHAINS[_sourceChainId].endpoint) return true;
        return false;
    }

    function isAuthorized(address _sender, uint _sourceChainId) public view returns (bool) {
        return isSelf(_sender, _sourceChainId);
    }

    receive() external payable {}
    fallback() external payable {}
}