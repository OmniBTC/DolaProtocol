// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibWormhole.sol";
import "../../libraries/LibPool.sol";
import "../../interfaces/IOmniPool.sol";

contract WormholeFacet {
    function sendDeposit(
        bytes memory tokenName,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = LibWormhole.omnipool(tokenName).depositTo(
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

    function sendWithdraw(
        bytes memory tokenName,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = LibWormhole.omnipool(tokenName).withdrawTo(
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
        bytes memory depositTokenName,
        uint256 depositAmount,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        bytes memory payload = LibWormhole
            .omnipool(depositTokenName)
            .depositAndWithdraw(
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
        LibWormhole.omnipool(payload.tokenName).innerWithdraw(
            payload.user,
            payload.amount
        );
    }

    // todo: add this to governance
    function addOmniPool(address pool) external {
        bytes memory tokenName = IOmniPool(pool).getTokenName();
        LibWormhole.addPool(tokenName, pool);
    }
}
