// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IBPSucker} from "./interfaces/IBPSucker.sol";
import {IBPSuckerRegistry, SuckerDeployerConfig, BPTokenConfig} from "./interfaces/IBPSuckerRegistry.sol";
import {JBOwnable, IJBProjects, IJBPermissions} from "@bananapus/ownable/src/JBOwnable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract BPSuckerRegistry is JBOwnable, IBPSuckerRegistry {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    error INVALID_DEPLOYER(address _deployer);

    // TODO: Replace with correct permission id.
    uint8 constant DEPLOY_SUCKERS_PERMISSION_ID = 100;

    uint256 constant SUCKER_EXISTS = 1;

    mapping(uint256 => EnumerableMap.AddressToUintMap) _suckersOf;

    mapping(address deployer => bool) public suckerDeployerIsAllowed;

    constructor(
        IJBProjects _projects,
        IJBPermissions _permissions
    ) JBOwnable(_projects, _permissions) {
        // Transfer ownership to projectID 1 owner (JBDAO).
        _transferOwnership(address(0), uint88(1));
    }

    function isSuckerOf(uint256 projectId, address suckerAddress) external view returns (bool) {
        return _suckersOf[projectId].get(suckerAddress) == SUCKER_EXISTS;
    }

    function suckersOf(uint256 projectId) external view returns (address[] memory) {
        return _suckersOf[projectId].keys();
    }

    function allowSuckerDeployer(address deployer) public override onlyOwner {
        suckerDeployerIsAllowed[deployer] = true;
    }

    /**
     * @notice deploy sucker(s) for a project.
     * @dev Requires the sender to have permission from/for the project.
     * @param projectId the projectId to create the sucker(s) for.
     * @param salt the salt being used to deploy the contract, has to be the same across chains.
     * @param configurations the configuration to deploy.
     * @return suckers the deployed sucker(s).
     */
    function deploySuckersFor(
        uint256 projectId,
        bytes32 salt,
        SuckerDeployerConfig[] calldata configurations
    )
        public
        override
        returns (address[] memory suckers)
    {
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: DEPLOY_SUCKERS_PERMISSION_ID
        });

        suckers = new address[](configurations.length);

        // This makes it so the sender has to be the same for both chains in order to link projects.
        salt = keccak256(abi.encode(msg.sender, salt));

        // Keep a reference to the number of sucker deployers.
        uint256 numberOfSuckerDeployers = configurations.length;

        // Keep a reference to the sucker deploy being iterated on.
        SuckerDeployerConfig memory configuration;

        for (uint256 i; i < numberOfSuckerDeployers; i++) {
            // Get the configuration being iterated on.
            configuration = configurations[i];

            // Make sure the deployer is allowed.
            if (!suckerDeployerIsAllowed[address(configuration.deployer)])
                revert INVALID_DEPLOYER(address(configuration.deployer));

            // Create the sucker.
            IBPSucker sucker = configuration.deployer.createForSender({_localProjectId: projectId, _salt: salt});
            suckers[i] = address(sucker);

            // Store the sucker as being deployed for this project.
            _suckersOf[projectId].set(address(sucker), SUCKER_EXISTS);
        
            // Keep a reference to the number of token configurations for the sucker.
            uint256 numberOfTokenConfigurations = configuration.tokenConfigurations.length;

            // Keep a reference to the token configurations being iterated on.
            BPTokenConfig memory tokenConfiguration;

            // Configure the tokens for the sucker.
            for (uint256 j; j < numberOfTokenConfigurations; j++) {
                // Get a reference to the configuration being iterated on.
                tokenConfiguration = configuration.tokenConfigurations[j];

                // Configure the sucker.
                sucker.configureToken(
                    BPTokenConfig({
                        localToken: tokenConfiguration.localToken,
                        remoteToken: tokenConfiguration.remoteToken,
                        minGas: tokenConfiguration.minGas,
                        minBridgeAmount: tokenConfiguration.minBridgeAmount
                    })
                );
            }
        }
    }
}