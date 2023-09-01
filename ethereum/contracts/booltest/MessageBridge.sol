// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract ERC165 is IERC165 {
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

interface IAnchor {
    function messenger() external view returns (address);

    function sendToMessenger(
        address payable refundAddress,
        bytes32 crossType,
        bytes memory extraFeed,
        uint32 dstChainId,
        bytes calldata payload
    ) external payable returns (bytes32 txUniqueIdentification);
}

interface IMessengerFee {
    struct Message {
        bytes32 txUniqueIdentification;
        bytes32 crossType;
        bytes32 srcAnchor;
        bytes bnExtraFeed;
        bytes32 dstAnchor;
        bytes payload;
    }

    function cptTotalFee(
        address srcAnchor,
        uint32 dstChainId,
        uint32 payloadSize,
        bytes32 crossType,
        bytes memory extraFeed
    ) external view returns (uint256 feeInNative);

    function receiveFromBool(
        Message memory message,
        bytes calldata signature
    ) external;
}

interface IMsgReceiver {
    struct Message {
        bytes32 txUniqueIdentification;
        bytes32 crossType;
        bytes32 srcAnchor;
        bytes bnExtraFeed;
        bytes32 dstAnchor;
        bytes payload;
    }

    function receiveFromBool(
        Message memory message,
        bytes calldata signature
    ) external;
}

interface IBoolConsumerBase is IERC165 {
    function anchor() external view returns (address);

    function receiveFromAnchor(bytes32 txUniqueIdentification, bytes memory payload) external;
}

abstract contract BoolConsumerBase is ERC165, IBoolConsumerBase {
    /** Erros */
    error NOT_ANCHOR(address wrongAnchor);

    /** Constants */
    bytes32 public constant PURE_MESSAGE = keccak256("PURE_MESSAGE");
    bytes32 public constant VALUE_MESSAGE = keccak256("VALUE_MESSAGE");


    /** BoolAMT Specific */
    address internal immutable _anchor;

    /** Constructor */
    constructor(address anchor_) {
        _anchor = anchor_;
    }

    /** Modifiers */
    modifier onlyAnchor() {
        _checkAnchor(msg.sender);
        _;
    }

    /** Key Function on the Source Chain */
    // solhint-disable-next-line no-empty-blocks
    function receiveFromAnchor(
        bytes32 txUniqueIdentification,
        bytes memory payload
    ) external virtual override onlyAnchor {}

    /** Key Function on the Destination Chain */
    function _sendAnchor(
        uint256 callValue,
        address payable refundAddress,
        bytes32 crossType,
        bytes memory extraFeed,
        uint32 dstChainId,
        bytes memory payload
    ) internal virtual returns (bytes32 txUniqueIdentification) {
        txUniqueIdentification = IAnchor(_anchor).sendToMessenger{value: callValue}(
            refundAddress,
            crossType,
            extraFeed,
            dstChainId,
            payload
        );
    }

    /** Internal Functions */
    function _checkAnchor(address targetAnchor) internal view {
        if (targetAnchor != _anchor) revert NOT_ANCHOR(targetAnchor);
    }

    /** View Functions */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IBoolConsumerBase).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function anchor() external view override returns (address) {
        return _anchor;
    }
}

contract MessageBridge is BoolConsumerBase {
    event SentMsg(bytes32 id, bytes msg);
    event ReceiveMsg(bytes32 id, bytes msg);
    event SoTransferFailed(bytes returnData);

    constructor(address _anchor) BoolConsumerBase(_anchor) {}

    // Calculate the cross-chain fee to be prepaid
    function calculateFee(
        uint32 dstChainId,
        uint32 len
    ) public view returns (uint256 fee) {
        address srcAnchor = _anchor;

        fee = IMessengerFee(IAnchor(srcAnchor).messenger()).cptTotalFee(
            srcAnchor,
            dstChainId,
            len,
            PURE_MESSAGE,
            bytes("")
        );
    }

    function send_msg(
        uint32 dstChainId,
        bytes memory payload
    ) external payable  {
        uint256 fee = calculateFee(dstChainId, uint32(payload.length));
        require(msg.value >= fee, "MessageBridge: INSUFFICIENT_FEE");

        bytes32 id = _sendAnchor(
            fee,
            payable(msg.sender),
            PURE_MESSAGE,
            "",
            dstChainId,
            payload
        );

        if (id != bytes32(0)) {
            emit SentMsg(id, payload);
        }
    }

    function receiveFromAnchor(
        bytes32 txUniqueIdentification,
        bytes memory payload
    ) external override {
        emit ReceiveMsg(txUniqueIdentification, payload);
    }

    function _sendAnchor(
        uint256 callValue,
        address payable refundAddress,
        bytes32 crossType,
        bytes memory extraFeed,
        uint32 dstChainId,
        bytes memory payload
    ) internal override returns (bytes32 txUniqueIdentification) {
        try IAnchor(_anchor).sendToMessenger{value: callValue}(
            refundAddress,
            crossType,
            extraFeed,
            dstChainId,
            payload
        ) returns(bytes32 id) {
            txUniqueIdentification = id;
        } catch (bytes memory returnData) {
            emit SoTransferFailed(returnData);

            txUniqueIdentification = bytes32(0);
        }
    }

    function getRevertMsg(bytes memory _returnData) public pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "Transaction reverted silently";
        assembly {
        // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }
}
