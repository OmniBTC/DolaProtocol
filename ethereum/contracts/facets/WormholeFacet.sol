// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibWormhole.sol";
import "../../libraries/LibPool.sol";
import "../../libraries/LibAsset.sol";
import "../../interfaces/IOmniPool.sol";
import "../../interfaces/IWormhole.sol";

contract WormholeFacet {
    function sendDeposit(
        bytes memory tokenName,
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external payable {
        address token = IOmniPool(LibWormhole.omnipool(tokenName))
            .getTokenAddress();
        if (!LibAsset.isNativeAsset(token)) {
            LibAsset.depositAsset(token, amount);
        }
        LibAsset.maxApproveERC20(
            IERC20(token),
            LibWormhole.omnipool(tokenName),
            amount
        );
        bytes memory payload = IOmniPool(LibWormhole.omnipool(tokenName))
            .depositTo(amount, appId, appPayload);
        IWormhole(LibWormhole.wormhole()).publishMessage{value: msg.value}(
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
        bytes memory payload = IOmniPool(LibWormhole.omnipool(tokenName))
            .withdrawTo(appId, appPayload);
        IWormhole(LibWormhole.wormhole()).publishMessage{value: msg.value}(
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
        address token = IOmniPool(LibWormhole.omnipool(depositTokenName))
            .getTokenAddress();
        if (!LibAsset.isNativeAsset(token)) {
            LibAsset.depositAsset(token, depositAmount);
        }
        LibAsset.maxApproveERC20(
            IERC20(token),
            LibWormhole.omnipool(depositTokenName),
            depositAmount
        );
        bytes memory payload = IOmniPool(LibWormhole.omnipool(depositTokenName))
            .depositAndWithdraw(
                depositAmount,
                withdrawPool,
                withdrawUser,
                withdrawTokenName,
                appId,
                appPayload
            );
        IWormhole(LibWormhole.wormhole()).publishMessage{value: msg.value}(
            LibWormhole.nonce(),
            payload,
            LibWormhole.finality()
        );
        LibWormhole.increaseNonce();
    }

    function receiveWithdraw(bytes memory vaa) public {
        (IWormhole.VM memory vm, , ) = IWormhole(LibWormhole.wormhole())
            .parseAndVerifyVM(vaa);
        require(
            !LibWormhole.isCompleteVAA(vm.hash),
            "withdraw already completed"
        );
        LibWormhole.setVAAComplete(vm.hash);

        LibPool.ReceiveWithdrawPayload memory payload = LibPool
            .decodeReceiveWithdrawPayload(vm.payload);
        IOmniPool(LibWormhole.omnipool(payload.tokenName)).innerWithdraw(
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
