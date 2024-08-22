// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";

import {JBSuckerDeployerConfig} from "../structs/JBSuckerDeployerConfig.sol";

interface IJBSuckerRegistry {
    event SuckerDeployedFor(uint256 projectId, address sucker, JBSuckerDeployerConfig configuration, address caller);
    event SuckerDeployerAllowed(address deployer, address caller);
    
    function DIRECTORY() external view returns (IJBDirectory);
    function PROJECTS() external view returns (IJBProjects);

    function isSuckerOf(uint256 projectId, address addr) external view returns (bool);
    function suckersOf(uint256 projectId) external view returns (address[] memory);
    function suckerDeployerIsAllowed(address deployer) external view returns (bool);

    function allowSuckerDeployer(address deployer) external;
    function deploySuckersFor(uint256 projectId, bytes32 salt, JBSuckerDeployerConfig[] memory configurations)
        external
        returns (address[] memory suckers);
}
