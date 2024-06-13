// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./JBOptimismSucker.sol";

contract JBBaseSucker is JBOptimismSucker {
    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    constructor(
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        JBAddToBalanceMode atbMode
    ) JBOptimismSucker(directory, tokens, permissions, peer, atbMode) {}

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainID() external view virtual override returns (uint256 chainId) {
        uint256 _localChainId = block.chainid;
        if (_localChainId == 1) return 8453;
        if (_localChainId == 8453) return 1;
        if (_localChainId == 11155111) return 84532;
        if (_localChainId == 84532) return 11155111;
    }
}
