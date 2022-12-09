// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../libraries/LibPool.sol";

contract OmniPool {
    uint16 public _chainId;
    uint256 public _balance;
    address public _bridge;
    address public _token;
    // use the token name defined by the omnicore
    bytes public _name;
    mapping(address => bool) private _allowances;

    modifier isBridge(address bridge) {
        require(_allowances[bridge], "Not bridge!");
        _;
    }

    constructor(
        address bridge,
        address token,
        bytes memory name
    ) {
        _bridge = bridge;
        _token = token;
        _name = name;
        _allowances[bridge] = true;
    }

    function decimals() public view returns (uint8) {
        return ERC20(_token).decimals();
    }

    function rely(address bridge) external isBridge(msg.sender) {
        _allowances[bridge] = true;
    }

    function deny(address bridge) external isBridge(msg.sender) {
        _allowances[bridge] = false;
    }

    function depositTo(
        uint256 amount,
        uint16 appId,
        bytes memory appPayload
    ) external returns (bytes memory) {
        ERC20(_token).transfer(address(this), amount);

        bytes memory poolPayload = LibPool.encodeSendDepositPayload(
            address(this),
            tx.origin,
            LibPool.fixAmountDecimals(amount, decimals()),
            _name,
            appId,
            appPayload
        );
        return poolPayload;
    }

    function withdrawTo(uint16 appId, bytes memory appPayload)
        external
        view
        returns (bytes memory)
    {
        bytes memory poolPayload = LibPool.encodeSendWithdrawPayload(
            address(this),
            tx.origin,
            _name,
            appId,
            appPayload
        );
        return poolPayload;
    }

    function innerWithdraw(address to, uint64 amount)
        external
        isBridge(msg.sender)
    {
        ERC20(_token).transferFrom(
            address(this),
            to,
            LibPool.restoreAmountDecimals(amount, decimals())
        );
    }

    function depositAndWithdraw(
        uint256 depositAmount,
        address withdrawPool,
        address withdrawUser,
        bytes memory withdrawTokenName,
        uint16 appId,
        bytes memory appPayload
    ) public returns (bytes memory) {
        ERC20(_token).transfer(address(this), depositAmount);

        bytes memory poolPayload = LibPool.encodeSendDepositAndWithdrawPayload(
            address(this),
            tx.origin,
            LibPool.fixAmountDecimals(depositAmount, decimals()),
            _name,
            withdrawPool,
            withdrawUser,
            withdrawTokenName,
            appId,
            appPayload
        );

        return poolPayload;
    }
}
