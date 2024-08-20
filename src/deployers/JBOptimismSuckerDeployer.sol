// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";

import {JBOptimismSucker} from "../JBOptimismSucker.sol";
import {JBAddToBalanceMode} from "../enums/JBAddToBalanceMode.sol";
import {IOPMessenger} from "../interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "../interfaces/IOPStandardBridge.sol";
import {IJBSucker} from "./../interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./../interfaces/IJBSuckerDeployer.sol";

/// @notice An `IJBSuckerDeployerFeeless` implementation to deploy `JBOptimismSucker` contracts.
contract JBOptimismSuckerDeployer is JBPermissioned, IJBSuckerDeployer {

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBOptimismSuckerDeployer_OnlySuckers();
    error JBOptimismSuckerDeployer_AlreadyConfigured();
    error JBOptimismSuckerDeployer_ZeroAddress();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory immutable override DIRECTORY;

    /// @notice Only this address can configure this deployer, can only be used once.
    address immutable override LAYER_SPECIFIC_CONFIGURATOR;

    /// @notice The contract that manages token minting and burning.
    IJBTokens immutable override TOKENS;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice The messenger used to send messages between the local and remote sucker.
    OPMessenger public override opMessenger;

    /// @notice The bridge used to bridge tokens between the local and remote chain.
    OPStandardBridge public override opBridge;

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public isSucker;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice A temporary storage slot used by suckers to maintain deterministic deploys.
    uint256 internal _tempIdStore;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    constructor(IJBDirectory directory, IJBTokens tokens, IJBPermissions permissions, address configurator)
        JBPermissioned(permissions)
    {
        if (configurator == address(0)) revert ZERO_ADDRESS();
        LAYER_SPECIFIC_CONFIGURATOR = configurator;
        DIRECTORY = directory;
        TOKENS = tokens;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment addresses would change.
    /// @notice messenger the OPMesssenger on this layer.
    /// @notice bridge the OPStandardBridge on this layer.
    function configureLayerSpecific(OPMessenger messenger, OPStandardBridge bridge) external {
        if (address(opMessenger) != address(0) || address(opBridge) != address(0)) {
            revert ALREADY_CONFIGURED();
        }
        // Configure these layer specific properties.
        // This is done in a separate call to make the deployment code chain agnostic.
        opMessenger = messenger;
        opBridge = bridge;
    }

    /// @notice Create a new `JBSucker` for a specific project.
    /// @dev Uses the sender address as the salt, which means the same sender must call this function on both chains.
    /// @param localProjectId The project's ID on the local chain.
    /// @param salt The salt to use for the `create2` address.
    /// @return sucker The address of the new sucker.
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IJBSucker sucker) {
        salt = keccak256(abi.encodePacked(msg.sender, salt));

        // Set for a callback to this contract.
        _tempIdStore = localProjectId;

        sucker = IJBSucker(
            address(
                new JBOptimismSucker{salt: salt}(DIRECTORY, TOKENS, PERMISSIONS, address(0), JBAddToBalanceMode.MANUAL)
            )
        );

        // TODO: See if resetting this value is cheaper than deletion
        // Delete after callback should complete.
        /* delete TEMP_ID_STORE; */

        isSucker[address(sucker)] = true;
    }
}
