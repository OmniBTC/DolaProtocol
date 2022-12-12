// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibWormhole.sol";
import "../../libraries/LibPool.sol";

contract WormholeFacet {
    function sendDeposit(
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = LibWormhole.omnipool().depositTo(
            amount,
            appId,
            appPayload
        );
        LibWormhole.wormhole().publishMessage{value: msg.value}(
            LibWormhole.nonce(),
            payload,
            LibWormhole.finality()
        );
        LibWormhole.increaseNonce();
    }

    function sendWithdraw(uint16 appId, bytes memory appPayload)
        external
        payable
    {
        bytes memory payload = LibWormhole.omnipool().withdrawTo(
            appId,
            appPayload
        );
        LibWormhole.wormhole().publishMessage{value: msg.value}(
            LibWormhole.nonce(),
            payload,
            LibWormhole.finality()
        );
        LibWormhole.increaseNonce();
    }

    function sendDepositAndWithdraw(
        uint256 depositAmount,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = LibWormhole.omnipool().depositAndWithdraw(
            depositAmount,
            withdrawPool,
            withdrawUser,
            withdrawTokenName,
            appId,
            appPayload
        );
        LibWormhole.wormhole().publishMessage{value: msg.value}(
            LibWormhole.nonce(),
            payload,
            LibWormhole.finality()
        );
        LibWormhole.increaseNonce();
    }

    function receiveWithdraw(bytes memory vaa) public {
        (IWormhole.VM memory vm, , ) = LibWormhole.wormhole().parseAndVerifyVM(
            vaa
        );
        require(
            !LibWormhole.isCompleteVAA(vm.hash),
            "withdraw already completed"
        );
        LibWormhole.setVAAComplete(vm.hash);

        LibPool.ReceiveWithdrawPayload memory payload = LibPool
            .decodeReceiveWithdrawPayload(vm.payload);
        LibWormhole.omnipool().innerWithdraw(payload.user, payload.amount);
    }
}
