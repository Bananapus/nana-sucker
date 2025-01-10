// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./JBSuckerDeployer.sol";
import "../interfaces/IJBArbitrumSuckerDeployer.sol";

import {JBArbitrumSucker} from "../JBArbitrumSucker.sol";
import {JBLayer} from "../enums/JBLayer.sol";
import {IArbGatewayRouter} from "../interfaces/IArbGatewayRouter.sol";
import {ARBAddresses} from "../libraries/ARBAddresses.sol";
import {ARBChains} from "../libraries/ARBChains.sol";

/// @notice An `IJBSuckerDeployerFeeless` implementation to deploy `JBOptimismSucker` contracts.
contract JBArbitrumSuckerDeployer is JBSuckerDeployer, IJBArbitrumSuckerDeployer {
    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice The layer that this contract is on.
    JBLayer public arbLayer;

    /// @notice The inbox used to send messages between the local and remote sucker.
    IInbox public override arbInbox;

    /// @notice The gateway router for the specific chain
    IArbGatewayRouter public override arbGatewayRouter;

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
        JBSuckerDeployer(directory, permissions, tokens, configurator, trusted_forwarder)
    {}

    //*********************************************************************//
    // ------------------------ internal views --------------------------- //
    //*********************************************************************//

    /// @notice Check if the layer specific configuration is set or not. Used as a sanity check.
    function _layerSpecificConfigurationIsSet() internal view override returns (bool) {
        return uint256(arbLayer) != uint256(0) || address(arbInbox) != address(0)
            || address(arbGatewayRouter) != address(0);
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment
    /// addresses would change.
    /// @notice messenger the OPMesssenger on this layer.
    /// @notice bridge the OPStandardBridge on this layer.
    function setChainSpecificConstants(JBLayer layer, IInbox inbox, IArbGatewayRouter gatewayRouter) external {
        if (_layerSpecificConfigurationIsSet()) {
            revert JBSuckerDeployer_AlreadyConfigured();
        }

        if (_msgSender() != LAYER_SPECIFIC_CONFIGURATOR) {
            revert JBSuckerDeployer_Unauthorized(_msgSender(), LAYER_SPECIFIC_CONFIGURATOR);
        }

        // Configure these layer specific properties.
        // This is done in a separate call to make the deployment code chain agnostic.
        arbLayer = layer;
        arbInbox = inbox;
        arbGatewayRouter = gatewayRouter;

        // Make sure the layer specific configuration is properly configured.
        if (!_layerSpecificConfigurationIsSet()) {
            revert JBSuckerDeployer_InvalidLayerSpecificConfiguration();
        }
    }
}
