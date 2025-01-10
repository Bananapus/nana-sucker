// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBSuckerDeployer} from "./../interfaces/IJBSuckerDeployer.sol";
import {IJBSucker} from "./../interfaces/IJBSucker.sol";

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";
import {JBSucker} from "../JBSucker.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/// @notice A base implementation for deploying suckers.
abstract contract JBSuckerDeployer is ERC2771Context, JBPermissioned, IJBSuckerDeployer {
    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice Only this address can configure this deployer, can only be used once.
    address public immutable override LAYER_SPECIFIC_CONFIGURATOR;

    /// @notice The contract that manages token minting and burning.
    IJBTokens public immutable override TOKENS;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public override isSucker;

    /// @notice The singleton used to clone suckers.
    JBSucker public singleton;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory The directory of terminals and controllers for projects.
    /// @param permissions The permissions contract for the deployer.
    /// @param tokens The contract that manages token minting and burning.
    /// @param configurator The address of the configurator.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        address configurator,
        address trusted_forwarder
    )
        ERC2771Context(trusted_forwarder)
        JBPermissioned(permissions)
    {
        DIRECTORY = directory;
        TOKENS = tokens;
        LAYER_SPECIFIC_CONFIGURATOR = configurator;

        // There has to be a configurator address or the layer specific configuration has to already be configured.
        if (configurator == address(0) && !_layerSpecificConfigurationIsSet()) {
            revert JBSuckerDeployer_ZeroConfiguratorAddress();
        }
    }

    //*********************************************************************//
    // ------------------------ internal views --------------------------- //
    //*********************************************************************//

    /// @notice Check if the layer specific configuration is set or not. Used as a sanity check.
    function _layerSpecificConfigurationIsSet() internal view virtual returns (bool);

    /// @notice The message's sender. Preferred to use over `msg.sender`.
    /// @return sender The address which sent this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    /// @notice The calldata. Preferred to use over `msg.data`.
    /// @return calldata The `msg.data` of this call.
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @dev ERC-2771 specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view virtual override(ERC2771Context, Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Configure the singleton instance that is used to clone suckers.
    /// @dev Can only be called *once* by the layer specific configurator.
    /// @param _singleton The address of the singleton.
    function configureSingleton(JBSucker _singleton) external {
        // Make sure only the configurator can call this function.
        if (_msgSender() != LAYER_SPECIFIC_CONFIGURATOR) {
            revert JBSuckerDeployer_Unauthorized(_msgSender(), LAYER_SPECIFIC_CONFIGURATOR);
        }

        // Ensure that the layer specific configuration is set.
        if (!_layerSpecificConfigurationIsSet()) {
            revert JBSuckerDeployer_LayerSpecificNotConfigured();
        }

        // Make sure the singleton is not already configured.
        if (address(singleton) != address(0)) revert JBSuckerDeployer_AlreadyConfigured();

        singleton = _singleton;
    }

    /// @notice Create a new `JBSucker` for a specific project.
    /// @dev Uses the sender address as the salt, which means the same sender must call this function on both chains.
    /// @param localProjectId The project's ID on the local chain.
    /// @param salt The salt to use for the `create2` address.
    /// @return sucker The address of the new sucker.
    function createForSender(
        uint256 localProjectId,
        bytes32 salt
    )
        external
        override(IJBSuckerDeployer)
        returns (IJBSucker sucker)
    {
        // Make sure that this deployer is configured properly.
        if (address(singleton) == address(0)) {
            revert JBSuckerDeployer_DeployerIsNotConfigured();
        }

        // Hash the salt with the sender address to ensure only a specific sender can create this sucker.
        salt = keccak256(abi.encodePacked(_msgSender(), salt));

        // Clone the singleton.
        sucker = IJBSucker(LibClone.cloneDeterministic(address(singleton), salt));

        // Mark it as a sucker that was deployed by this deployer.
        isSucker[address(sucker)] = true;

        // Initialize the clone.
        JBSucker(payable(address(sucker))).initialize(localProjectId);
    }
}
