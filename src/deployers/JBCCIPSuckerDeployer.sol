// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./JBSuckerDeployer.sol";
import "../interfaces/IJBArbitrumSuckerDeployer.sol";

import {JBCCIPSucker} from "../JBCCIPSucker.sol";
import {JBAddToBalanceMode} from "../enums/JBAddToBalanceMode.sol";
import {IJBSucker} from "./../interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./../interfaces/IJBSuckerDeployer.sol";
import {IJBCCIPSuckerDeployer} from "./../interfaces/IJBCCIPSuckerDeployer.sol";
import {ICCIPRouter} from "src/interfaces/ICCIPRouter.sol";
import {CCIPHelper} from "src/libraries/CCIPHelper.sol";

/// @notice An `IJBSuckerDeployer` implementation to deploy contracts.
contract JBCCIPSuckerDeployer is JBSuckerDeployer, IJBCCIPSuckerDeployer {
    error JBCCIPSuckerDeployer_InvalidCCIPRouter(address router);

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice Store the remote chain id
    uint256 public ccipRemoteChainId;

    /// @notice The remote chain selector target of all sucker deployed by this contract.
    uint64 public ccipRemoteChainSelector;

    /// @notice Store the address of the CCIP router for this chain.
    ICCIPRouter public ccipRouter;

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
        return ccipRemoteChainId != 0 && ccipRemoteChainSelector != 0 && address(ccipRouter) != address(0);
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment
    /// addresses would change.
    /// TODO natspec

    function setChainSpecificConstants(
        uint256 remoteChainId,
        uint64 remoteChainSelector,
        ICCIPRouter router
    )
        external
    {
        if (_layerSpecificConfigurationIsSet()) {
            revert JBSuckerDeployer_AlreadyConfigured();
        }

        if (_msgSender() != LAYER_SPECIFIC_CONFIGURATOR) {
            revert JBSuckerDeployer_Unauthorized(_msgSender(), LAYER_SPECIFIC_CONFIGURATOR);
        }

        ccipRemoteChainId = remoteChainId;
        ccipRemoteChainSelector = remoteChainSelector;
        ccipRouter = router;

        // Make sure the layer specific configuration is properly configured.
        if (!_layerSpecificConfigurationIsSet()) {
            revert JBSuckerDeployer_InvalidLayerSpecificConfiguration();
        }

        emit CCIPConstantsSet(address(ccipRouter), ccipRemoteChainId, ccipRemoteChainSelector, _msgSender());
    }
}
