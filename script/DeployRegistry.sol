// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, stdJson} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BPSuckerRegistry, IJBProjects, IJBPermissions} from "./../src/BPSuckerRegistry.sol";

contract DeployRegistry is Script {
    string DEPLOYMENT_JSON;

    function setUp() public {
        // Get the JB deployment JSON.
        DEPLOYMENT_JSON = string.concat(
            "node_modules/@bananapus/core/broadcast/Deploy.s.sol/", Strings.toString(block.chainid), "/run-latest.json"
        );
    }

    function run() public {
        vm.startBroadcast();
        new BPSuckerRegistry(
            IJBProjects(_getDeploymentAddress(DEPLOYMENT_JSON, "JBProjects")),
            IJBPermissions(_getDeploymentAddress(DEPLOYMENT_JSON, "JBPermissions"))
        );
        vm.stopBroadcast();
    }

    /**
     * @notice Get the address of a contract that was deployed by the Deploy script.
     *     @dev Reverts if the contract was not found.
     *     @param _path The path to the deployment file.
     *     @param _contractName The name of the contract to get the address of.
     *     @return The address of the contract.
     */
    function _getDeploymentAddress(string memory _path, string memory _contractName) internal view returns (address) {
        string memory _deploymentJson = vm.readFile(_path);
        uint256 _nOfTransactions = stdJson.readStringArray(_deploymentJson, ".transactions").length;

        for (uint256 i = 0; i < _nOfTransactions; i++) {
            string memory _currentKey = string.concat(".transactions", "[", Strings.toString(i), "]");
            string memory _currentContractName =
                stdJson.readString(_deploymentJson, string.concat(_currentKey, ".contractName"));

            if (keccak256(abi.encodePacked(_currentContractName)) == keccak256(abi.encodePacked(_contractName))) {
                return stdJson.readAddress(_deploymentJson, string.concat(_currentKey, ".contractAddress"));
            }
        }

        revert(
            string.concat("Could not find contract with name '", _contractName, "' in deployment file '", _path, "'")
        );
    }
}