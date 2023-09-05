// Copyright (c) OmniBTC, Inc.
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../libraries/LibAsset.sol";
import "../libraries/LibPoolCodec.sol";
import "../libraries/LibLendingCodec.sol";
import "../libraries/LibSystemCodec.sol";
import "../libraries/LibGovCodec.sol";
import "../libraries/LibBoolAdapterVerify.sol";
import "../libraries/LibBytes.sol";
import "../../interfaces/IBoolConsumerBase.sol";
import "../../interfaces/IBoolAdapterPool.sol";
import "../../interfaces/IERC165.sol";
import "../../interfaces/IBoolAnchor.sol";
import "../../interfaces/IBoolMessenger.sol";
import "./DolaPool.sol";

contract BoolAdapterPool is ERC165, IBoolConsumerBase, IBoolAdapterPool {
    bytes32 public constant PURE_MESSAGE = keccak256("PURE_MESSAGE");

    /// Storage

    // Bool Anchor address
    IBoolAnchor public immutable boolAnchor;
    // Dola chain id
    uint16 public immutable dolaChainId;
    // Dola pool
    DolaPool public dolaPool;

    uint32 public immutable suiChainId;

    // Used to verify that the message has been processed
    mapping(bytes32 => bool) public consumedMsgs;
    // Used to verify relayer authority
    mapping(address => bool) public registeredRelayers;
    // Used to receive relayer fee
    address[] public relayers;

    event PoolWithdrawEvent(
        uint64 nonce,
        uint16 sourceChainId,
        uint16 dstChianId,
        bytes poolAddress,
        bytes receiver,
        uint64 amount
    );

    constructor(
        IBoolAnchor _anchor,
        uint16 _dolaChainId,
        DolaPool _dolaPool,
        address _initialRelayer,
        uint32 _suiChainId
    ) {
        boolAnchor = _anchor;
        dolaChainId = _dolaChainId;
        suiChainId = _suiChainId;

        if (address(_dolaPool) == address(0x0)) {
            // First deploy pool
            dolaPool = new DolaPool(_dolaChainId, address(this));
        } else {
            // Upgrade
            dolaPool = _dolaPool;
        }

        registeredRelayers[_initialRelayer] = true;
        relayers.push(_initialRelayer);
    }

    /// Modifiers

    modifier onlyRelayer() {
        require(registeredRelayers[msg.sender], "NOT RELAYER");
        _;
    }

    /// Call by governance

    function getDolaContract() public view returns (uint256) {
        return uint256(uint160(address(this)));
    }

    function registerSpender(bytes memory internal_payload) internal {
        LibPoolCodec.ManagePoolPayload memory payload = LibPoolCodec
            .decodeManagePoolPayload(internal_payload);
        require(
            payload.poolCallType == LibPoolCodec.POOL_REGISTER_SPENDER,
            "INVALID CALL TYPE"
        );
        require(payload.dolaChainId == dolaChainId, "INVALID DOLA CHAIN");
        dolaPool.registerSpender(address(uint160(payload.dolaContract)));
    }

    function deleteSpender(bytes memory internal_payload) internal {
        LibPoolCodec.ManagePoolPayload memory payload = LibPoolCodec
            .decodeManagePoolPayload(internal_payload);
        require(
            payload.poolCallType == LibPoolCodec.POOL_DELETE_SPENDER,
            "INVALID CALL TYPE"
        );
        require(payload.dolaChainId == dolaChainId, "INVALID DOLA CHAIN");
        dolaPool.deleteSpender(address(uint160(payload.dolaContract)));
    }

    function registerRelayer(bytes memory internal_payload) internal {
        LibGovCodec.RelayerPayload memory payload = LibGovCodec
            .decodeRelayerPayload(internal_payload);

        require(payload.opcode == LibGovCodec.ADD_RELAYER_OPCODE);
        require(
            payload.relayer.dolaChainId == dolaChainId,
            "INVALID DOLA CHAIN"
        );
        address relayer = LibDolaTypes.dolaAddressToAddress(payload.relayer);
        require(!registeredRelayers[relayer], "RELAYER ALREADY REGISTERED");
        registeredRelayers[relayer] = true;
        relayers.push(relayer);
    }

    function removeRelayer(bytes memory internal_payload) internal {
        LibGovCodec.RelayerPayload memory payload = LibGovCodec
            .decodeRelayerPayload(internal_payload);

        require(payload.opcode == LibGovCodec.REMOVE_RELAYER_OPCODE);
        require(
            payload.relayer.dolaChainId == dolaChainId,
            "INVALID DOLA CHAIN"
        );
        address relayer = LibDolaTypes.dolaAddressToAddress(payload.relayer);

        require(registeredRelayers[relayer], "RELAYER NOT REGISTERED");
        registeredRelayers[relayer] = false;
        for (uint256 i = 0; i < relayers.length; i++) {
            if (relayers[i] == relayer) {
                relayers[i] = relayers[relayers.length - 1];
                relayers.pop();
                break;
            }
        }
    }

    function receiveWithdraw(bytes memory internal_payload) internal {
        LibPoolCodec.WithdrawPayload memory payload = LibPoolCodec
            .decodeWithdrawPayload(internal_payload);
        dolaPool.withdraw(payload.user, payload.amount, payload.pool);

        emit PoolWithdrawEvent(
            payload.nonce,
            payload.sourceChainId,
            payload.pool.dolaChainId,
            payload.pool.externalAddress,
            payload.user.externalAddress,
            payload.amount
        );
    }

    function dispatch(bytes memory raw_payload) internal {
        require(raw_payload.length > 0, "payload must not be empty");

        uint8 op_code = uint8(raw_payload[raw_payload.length - 1]);
        bytes memory internal_payload = LibBytes.slice(
            raw_payload,
            0,
            raw_payload.length - 2
        );

        if (op_code == LibBoolAdapterVerify.REMAPPING_ADD_RELAYER_OPCODE) {
            registerRelayer(internal_payload);
        } else if (op_code == LibBoolAdapterVerify.REMAPPING_REMOVE_RELAYER_OPCODE) {
            removeRelayer(internal_payload);
        } else if (op_code == LibBoolAdapterVerify.REMAPPING_POOL_REGISTER_SPENDER) {
            registerSpender(internal_payload);
        } else if (op_code == LibBoolAdapterVerify.REMAPPING_POOL_DELETE_SPENDER) {
            deleteSpender(internal_payload);
        } else if (op_code == LibBoolAdapterVerify.REMAPPING_POOL_WITHDRAW) {
            receiveWithdraw(internal_payload);
        } else {
            revert("invalid remapping opcode");
        }
    }


    /// Call by application

    /// Send deposit by application
    function sendDeposit(
        address token,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes32) {
        uint256 boolFee = boolMessageFee(
            token,
            amount,
            appId,
            appPayload
        );
        require(msg.value >= boolFee, "FEE NOT ENOUGH");

        // Deposit assets to the pool and perform amount checks
        LibAsset.depositAsset(token, amount);
        if (!LibAsset.isNativeAsset(token)) {
            LibAsset.maxApproveERC20(IERC20(token), address(dolaPool), amount);
        }

        bytes memory payload = dolaPool.deposit{value: msg.value - boolFee}(
            token,
            amount,
            appId,
            appPayload
        );

        return IBoolAnchor(boolAnchor).sendToMessenger{value: boolFee}(
            payable(tx.origin),
            PURE_MESSAGE,
            "",
            suiChainId,
            payload
        );
    }

    /// Send message that do not involve incoming or outgoing funds by application
    function sendMessage(
        uint16 appId,
        bytes memory appPayload
    ) external payable returns (bytes32)
    {
        uint256 boolFee = boolMessageFee(
            address(0),
            0,
            appId,
            appPayload
        );
        require(msg.value >= boolFee, "FEE NOT ENOUGH");

        bytes memory payload = dolaPool.sendMessage(appId, appPayload);

        /// If much sufficient, return the rest to the refundAddress
        return IBoolAnchor(boolAnchor).sendToMessenger{value: msg.value}(
            payable(tx.origin),
            PURE_MESSAGE,
            "",
            suiChainId,
            payload
        );
    }

    function getOneRelayer(uint64 nonce) external view returns (address) {
        return relayers[nonce % relayers.length];
    }

    /// Get nonce
    function getNonce() external returns (uint64) {
        return dolaPool.getNonce();
    }

    /// Get messenger address
    function boolMessenger() public view returns (address) {
        return IBoolAnchor(boolAnchor).messenger();
    }

    /// Calculate the cross-chain fee to be prepaid
    function boolMessageFee(
        address token,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) public view returns (uint256 fee) {
        uint payload_len = 0;

        if (address(0) == token) {
            bytes memory messagePayload = LibPoolCodec.encodeSendMessagePayload(
                LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
                appId,
                appPayload
            );

            payload_len = messagePayload.length;
        } else {
            bytes memory poolPayload = LibPoolCodec.encodeDepositPayload(
                LibDolaTypes.addressToDolaAddress(dolaChainId, token),
                LibDolaTypes.addressToDolaAddress(dolaChainId, tx.origin),
                LibDecimals.fixAmountDecimals(
                    amount,
                    LibAsset.queryDecimals(token)
                ),
                appId,
                appPayload
            );

            payload_len = poolPayload.length;
        }

        fee = IBoolMessenger(boolMessenger()).cptTotalFee(
            address(boolAnchor),
            suiChainId,
            uint32(payload_len),
            PURE_MESSAGE,
            bytes("")
        );
    }

    function getLastByte(bytes memory data) public pure returns (bytes1) {
        require(data.length > 0, "Data must not be empty");
        return data[data.length - 1];
    }

    function anchor() external view returns (address) {
        return address(boolAnchor);
    }

    /// Our relayer will call messenger.receiveFromBool(message, signature)
    ///
    /// In Bool Messenger Contract
    /// function receiveFromBool(
    ///    Message memory message,
    ///    bytes calldata signature
    /// ) external override nonReentrant
    ///
    /// In the receiveFromBool function:
    /// (1) verify message and signature
    /// (2) duplicated txUniqueIdentification
    /// (3) call back our receiveFromAnchor function
    function receiveFromAnchor(
        bytes32 txUniqueIdentification,
        bytes memory raw_payload
    ) external {
        require(registeredRelayers[tx.origin], "NOT RELAYER");

        LibBoolAdapterVerify.replayProtect(
            consumedMsgs,
            txUniqueIdentification,
            raw_payload
        );

        dispatch(raw_payload);
    }


    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IBoolConsumerBase).interfaceId ||
            super.supportsInterface(interfaceId);
    }

}
