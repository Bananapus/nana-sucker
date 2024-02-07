// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../BPOptimismSucker.sol";

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract BPOptimismSuckerDeployer {
    IJBPrices immutable PRICES;
    IJBRulesets immutable RULESETS;
    OPMessenger immutable MESSENGER;
    OpStandardBridge immutable BRIDGE;
    IJBDirectory immutable DIRECTORY;
    IJBTokens immutable TOKENS;
    IJBPermissions immutable PERMISSIONS;
    bytes32 immutable SUCKER_BYTECODE_HASH;

    constructor(
        IJBPrices _prices,
        IJBRulesets _rulesets,
        OPMessenger _messenger,
        OpStandardBridge _bridge,
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions
    ) {
        PRICES = _prices;
        RULESETS = _rulesets;
        MESSENGER = _messenger;
        BRIDGE = _bridge;
        DIRECTORY = _directory;
        TOKENS = _tokens;
        PERMISSIONS = _permissions;

        SUCKER_BYTECODE_HASH = keccak256(type(BPOptimismSucker).creationCode);
    }

    function createForSender(
        uint256 _localProjectId,
        bytes32 _salt
    ) external returns (address) {
        _salt = keccak256(abi.encodePacked(msg.sender, _salt));

        address _computed = Create2.computeAddress(_salt, SUCKER_BYTECODE_HASH);
        address _sucker = address(new BPOptimismSucker{salt: _salt}(
            PRICES,
            RULESETS,
            MESSENGER,
            BRIDGE,
            DIRECTORY,
            TOKENS,
            PERMISSIONS,
            _computed,
            _localProjectId
        ));

        // Sanity-check: Make sure we actually deployed to the computed address.
        assert(_computed == _sucker);
        return _sucker;
    }
}