// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/JBSucker.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";
import /* {*} from */ "@bananapus/core/test/helpers/TestBaseWorkflow.sol";

contract SuckerEmergencyTest is Test {
    using stdStorage for StdStorage;

    address constant DIRECTORY = address(600);
    address constant PERMISSIONS = address(800);
    address constant TOKENS = address(700);
    address constant CONTROLLER = address(900);
    address constant PROJECT = address(1000);
    address constant FORWARDER = address(1100);

    function setUp() public {
        vm.label(DIRECTORY, "MOCK_DIRECTORY");
        vm.label(PERMISSIONS, "MOCK_PERMISSIONS");
        vm.label(TOKENS, "MOCK_TOKENS");
        vm.label(CONTROLLER, "MOCK_CONTROLLER");
        vm.label(PROJECT, "MOCK_PROJECT");
    }

    function testHelloWorld() external {
        _createTestSucker(1, "");
    }

    /// @notice Ensures that if a sucker is deprecated and a claim is valid that a user can withdraw their deposit.
    function testEmergencyExitWhenDeprecated(bool setAsDeprecated, bool isValidClaim, JBClaim memory claim) external {
        uint256 projectId = 1;
        TestSucker sucker = _createTestSucker(projectId, "");

        // Mock the Directory.
        vm.mockCall(DIRECTORY, abi.encodeCall(IJBDirectory.PROJECTS, ()), abi.encode(PROJECT));
        // Mock the owner of the project.
        vm.mockCall(PROJECT, abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(address(this)));

        // Set the outbox balance to be atleast the same as the attempted exit amount.
        sucker.test_setOutboxBalance(claim.token, claim.leaf.terminalTokenAmount);

        // Set the state of the sucker to be deprecated.
        if (setAsDeprecated) {
            uint256 deprecationTimestamp = block.timestamp + 14 days;
            sucker.setDeprecation(uint40(deprecationTimestamp));

            // Foward until its deprecated.
            vm.warp(deprecationTimestamp);
        }

        // Mock the calls the sucker does to mint the tokens to the user.
        vm.mockCall(DIRECTORY, abi.encodeCall(IJBDirectory.controllerOf, (projectId)), abi.encode(CONTROLLER));
        vm.mockCall(
            CONTROLLER,
            abi.encodeCall(
                IJBController.mintTokensOf, (projectId, claim.leaf.projectTokenCount, claim.leaf.beneficiary, "", false)
            ),
            abi.encode(claim.leaf.projectTokenCount)
        );

        // This ensures that if either the claim is considered invalid or that if the sucker was not deprecated that the
        // emergency exit would not work.
        sucker.test_setNextMerkleCheckToBe(isValidClaim);
        if (!isValidClaim || !setAsDeprecated) {
            vm.expectRevert();
        }

        // Attempt to emergency exit.
        sucker.exitThroughEmergencyHatch(claim);

        // Attempt to double exit.
        vm.expectRevert();
        sucker.exitThroughEmergencyHatch(claim);
    }

    /// @notice Ensures that if a sucker is send disabled and a claim is valid that a user can withdraw their deposit.
    function testEmergencyExitWhenSendingDisabled(
        bool sendDisabled,
        bool isValidClaim,
        JBClaim memory claim
    )
        external
    {
        uint256 projectId = 1;
        TestSucker sucker = _createTestSucker(projectId, "");

        // Mock the Directory.
        vm.mockCall(DIRECTORY, abi.encodeCall(IJBDirectory.PROJECTS, ()), abi.encode(PROJECT));
        // Mock the owner of the project.
        vm.mockCall(PROJECT, abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(address(this)));

        // Set the outbox balance to be atleast the same as the attempted exit amount.
        sucker.test_setOutboxBalance(claim.token, claim.leaf.terminalTokenAmount);

        // Set the state of the sucker to be deprecated.
        if (sendDisabled) {
            uint256 deprecationTimestamp = block.timestamp + 14 days;
            sucker.setDeprecation(uint40(deprecationTimestamp));

            // Foward until sending is disabled, which is the next block.
            vm.warp(block.timestamp + 1);
        }

        // Mock the calls the sucker does to mint the tokens to the user.
        vm.mockCall(DIRECTORY, abi.encodeCall(IJBDirectory.controllerOf, (projectId)), abi.encode(CONTROLLER));
        vm.mockCall(
            CONTROLLER,
            abi.encodeCall(
                IJBController.mintTokensOf, (projectId, claim.leaf.projectTokenCount, claim.leaf.beneficiary, "", false)
            ),
            abi.encode(claim.leaf.projectTokenCount)
        );

        // This ensures that if either the claim is considered invalid or that if the sucker was not deprecated that the
        // emergency exit would not work.
        sucker.test_setNextMerkleCheckToBe(isValidClaim);
        if (!isValidClaim || !sendDisabled) {
            vm.expectRevert();
        }

        // Attempt to emergency exit.
        sucker.exitThroughEmergencyHatch(claim);

        // Attempt to double exit.
        vm.expectRevert();
        sucker.exitThroughEmergencyHatch(claim);
    }

    /// @notice Ensures that users can exit on the local chain if the emergency hatch is opened for the token.
    function testEmergencyExitWhenEmergencyHatchOpenForToken(
        bool tokenAllowEmergencyHatch,
        bool isValidClaim,
        JBClaim memory claim
    )
        external
    {
        uint256 projectId = 1;
        TestSucker sucker = _createTestSucker(projectId, "");

        // Mock the Directory.
        vm.mockCall(DIRECTORY, abi.encodeCall(IJBDirectory.PROJECTS, ()), abi.encode(PROJECT));
        // Mock the owner of the project.
        vm.mockCall(PROJECT, abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(address(this)));

        // Set the outbox balance to be atleast the same as the attempted exit amount.
        sucker.test_setOutboxBalance(claim.token, claim.leaf.terminalTokenAmount);

        // Open the emergency hatch for the token if set for this test.
        if (tokenAllowEmergencyHatch) {
            address[] memory tokens = new address[](1);
            tokens[0] = claim.token;

            sucker.enableEmergencyHatchFor(tokens);
        }

        // Mock the calls the sucker does to mint the tokens to the user.
        vm.mockCall(DIRECTORY, abi.encodeCall(IJBDirectory.controllerOf, (projectId)), abi.encode(CONTROLLER));
        vm.mockCall(
            CONTROLLER,
            abi.encodeCall(
                IJBController.mintTokensOf, (projectId, claim.leaf.projectTokenCount, claim.leaf.beneficiary, "", false)
            ),
            abi.encode(claim.leaf.projectTokenCount)
        );

        // This ensures that if either the claim is considered invalid or that if the sucker was not deprecated that the
        // emergency exit would not work.
        sucker.test_setNextMerkleCheckToBe(isValidClaim);
        if (!isValidClaim || !tokenAllowEmergencyHatch) {
            vm.expectRevert();
        }

        // Attempt to emergency exit.
        sucker.exitThroughEmergencyHatch(claim);

        // Attempt to double exit.
        vm.expectRevert();
        sucker.exitThroughEmergencyHatch(claim);
    }

    /// @notice tests that the deprecation can be set, changed and cancelled.
    function testCancelDeprecation(uint40 currentTime, uint40 deprecateAt, uint40 changeDeprecationTo) external {
        uint40 messagingDelay = 14 days;
        // The time that we have to change the deprecation.
        uint40 bufferTime;
        // Ensure that none of the math overflows which would cause unexpected test results.
        vm.assume(type(uint40).max - messagingDelay > currentTime);
        vm.assume(type(uint40).max - messagingDelay > deprecateAt);
        vm.assume(type(uint40).max - messagingDelay > changeDeprecationTo);
        // Ensure that the inputs are within the expected bounds.
        vm.assume(currentTime + messagingDelay < deprecateAt);
        vm.assume(deprecateAt + messagingDelay < changeDeprecationTo || changeDeprecationTo == 0);
        bufferTime = deprecateAt - messagingDelay - currentTime;

        uint256 projectId = 1;
        TestSucker sucker = _createTestSucker(projectId, "");

        // Mock the Directory.
        vm.mockCall(DIRECTORY, abi.encodeCall(IJBDirectory.PROJECTS, ()), abi.encode(PROJECT));
        // Mock the owner of the project.
        vm.mockCall(PROJECT, abi.encodeCall(IERC721.ownerOf, (projectId)), abi.encode(address(this)));

        // Set the time at which the deprecation call is done.
        vm.warp(currentTime);
        // Set the deprecation to be at a future time.
        sucker.setDeprecation(uint40(deprecateAt));

        // Foward to a time before its fully deprecated..
        vm.warp(currentTime + bufferTime - 1);
        // The state should be `DEPRECATION_PENDING`.
        assertEq(uint8(sucker.state()), 1);
        // Change the time at which it deprecates
        sucker.setDeprecation(changeDeprecationTo);
    }

    function _createTestSucker(uint256 projectId, bytes32 salt) internal returns (TestSucker) {
        // Singleton.
        TestSucker singleton = new TestSucker(
            IJBDirectory(DIRECTORY),
            IJBPermissions(PERMISSIONS),
            IJBTokens(TOKENS),
            JBAddToBalanceMode.MANUAL,
            FORWARDER
        );
        vm.label(address(singleton), "SUCKER_SINGLETON");

        // Clone the singleton and initialize the clone.
        TestSucker sucker = TestSucker(payable(address(LibClone.cloneDeterministic(address(singleton), salt))));
        vm.label(address(sucker), "SUCKER");
        sucker.initialize(projectId);

        return TestSucker(sucker);
    }
}

contract TestSucker is JBSucker {
    bool nextCheckShouldPass;

    /// @param directory A contract storing directories of terminals and controllers for each project.
    /// @param tokens A contract that manages token minting and burning.
    /// @param permissions A contract storing permissions.
    /// @param addToBalanceMode The mode of adding tokens to balance.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        JBAddToBalanceMode addToBalanceMode,
        address forwarder
    )
        JBSucker(directory, permissions, tokens, addToBalanceMode, forwarder)
    {}

    function _sendRootOverAMB(
        uint256 transportPayment,
        uint256,
        address token,
        uint256 amount,
        JBRemoteToken memory remoteToken,
        JBMessageRoot memory message
    )
        internal
        override
    {}

    function _isRemotePeer(address sender) internal override returns (bool valid) {
        return sender == peer();
    }

    function peerChainId() external view virtual override returns (uint256) {
        return block.chainid;
    }

    /// @notice Validates a branch root against the expected root.
    /// @dev This is a virtual function to allow tests to override the behavior, it should never be overwritten
    /// otherwise.
    function _validateBranchRoot(
        bytes32 expectedRoot,
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        address beneficiary,
        uint256 index,
        bytes32[_TREE_DEPTH] calldata leaves
    )
        internal
        virtual
        override
    {
        // If the next check should fail, then we forward the call.
        if (!nextCheckShouldPass) {
            super._validateBranchRoot(expectedRoot, projectTokenCount, terminalTokenAmount, beneficiary, index, leaves);
        }

        // Set it to be false again.
        nextCheckShouldPass = false;
    }

    function test_setNextMerkleCheckToBe(bool _nextCheckShouldPass) external {
        nextCheckShouldPass = _nextCheckShouldPass;
    }

    function test_setOutboxBalance(address token, uint256 amount) external {
        _outboxOf[token].balance = amount;
    }
}
