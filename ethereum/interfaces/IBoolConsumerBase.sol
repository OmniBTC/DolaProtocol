// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC165.sol";

interface IBoolConsumerBase is IERC165 {
    function anchor() external view returns (address);

    function receiveFromAnchor(
        bytes32 txUniqueIdentification,
        bytes memory payload
    ) external;
}