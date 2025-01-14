// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import "../../src/JBSucker.sol";
import "../../src/deployers/JBOptimismSuckerDeployer.sol";

import {JBLeaf} from "../../src/structs/JBLeaf.sol";
import {JBClaim} from "../../src/structs/JBClaim.sol";

contract MerkleUnitTest is JBSucker, Test {
    using MerkleLib for MerkleLib.Tree;

    bytes32[32] _proof;

    constructor()
        // OPMessenger(address(500)),
        // OPStandardBridge(address(550)),
        JBSucker(
            IJBDirectory(address(600)),
            IJBPermissions(address(800)),
            IJBTokens(address(700)),
            JBAddToBalanceMode.MANUAL,
            address(0)
        )
    // self.initialize(.NATIVE_TOKEN, JBConstants.NATIVE_TOKEN, JBConstants.NATIVE_TOKEN)
    {
        // initialize({peer: address(this), projectId: 1});
    }

    function setUp() public {
        // Insert some items into the queue
        // Index 0
        _insertIntoTree(8 ether, JBConstants.NATIVE_TOKEN, 15 ether, address(1000));
        // Index 1
        _insertIntoTree(0.1 ether, JBConstants.NATIVE_TOKEN, 200 ether, address(999));
        // Index 2
        _insertIntoTree(5 ether, JBConstants.NATIVE_TOKEN, 5 ether, address(120));

        // Pre-computed proof thats valid for the above data.
        _proof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        _proof[1] = 0x15d682413b76d69d3a9f37321d80938e54900b74e3f119c027ed87dcec1a935b;
        _proof[2] = 0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30;
        _proof[3] = 0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85;
        _proof[4] = 0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344;
        _proof[5] = 0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d;
        _proof[6] = 0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968;
        _proof[7] = 0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83;
        _proof[8] = 0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af;
        _proof[9] = 0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0;
        _proof[10] = 0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5;
        _proof[11] = 0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892;
        _proof[12] = 0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c;
        _proof[13] = 0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb;
        _proof[14] = 0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc;
        _proof[15] = 0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2;
        _proof[16] = 0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f;
        _proof[17] = 0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a;
        _proof[18] = 0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0;
        _proof[19] = 0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0;
        _proof[20] = 0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2;
        _proof[21] = 0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9;
        _proof[22] = 0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377;
        _proof[23] = 0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652;
        _proof[24] = 0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef;
        _proof[25] = 0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d;
        _proof[26] = 0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0;
        _proof[27] = 0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e;
        _proof[28] = 0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e;
        _proof[29] = 0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322;
        _proof[30] = 0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735;
        _proof[31] = 0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9;
    }

    function test_insertIntoTree() public {
        // Queue the item.
        _insertIntoTree(10 ether, JBConstants.NATIVE_TOKEN, 10 ether, address(1337));
    }

    function test_validate() public {
        // Move outbound root to inbound root.
        _inboxOf[JBConstants.NATIVE_TOKEN] =
            JBInboxTreeRoot({nonce: 0, root: _outboxOf[JBConstants.NATIVE_TOKEN].tree.root()});

        bytes32[32] memory __proof = _proof;

        // Mock the token minting.
        address _mockController = address(900);
        vm.mockCall(
            address(DIRECTORY), abi.encodeCall(IJBDirectory.controllerOf, (projectId())), abi.encode(_mockController)
        );
        vm.mockCall(
            _mockController,
            abi.encodeCall(IJBController.mintTokensOf, (projectId(), 5 ether, address(120), "", false)),
            abi.encode(0)
        );

        // Attempt to validate proof.
        JBSucker(this).claim(
            JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({index: 2, beneficiary: address(120), projectTokenCount: 5 ether, terminalTokenAmount: 5 ether}),
                proof: __proof
            })
        );
    }

    function test_validate_only_once() public {
        // Move outbound root to inbound root.
        _inboxOf[JBConstants.NATIVE_TOKEN] =
            JBInboxTreeRoot({nonce: 0, root: _outboxOf[JBConstants.NATIVE_TOKEN].tree.root()});

        bytes32[32] memory __proof = _proof;

        // Mock the token minting.
        address _mockController = address(900);
        vm.mockCall(
            address(DIRECTORY), abi.encodeCall(IJBDirectory.controllerOf, (projectId())), abi.encode(_mockController)
        );
        vm.mockCall(
            _mockController,
            abi.encodeCall(IJBController.mintTokensOf, (projectId(), 5 ether, address(120), "", false)),
            abi.encode(0)
        );

        // Attempt to validate proof.
        JBSucker(this).claim(
            JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({index: 2, beneficiary: address(120), projectTokenCount: 5 ether, terminalTokenAmount: 5 ether}),
                proof: __proof
            })
        );

        // Attempt to do it again.
        vm.expectRevert();
        JBSucker(this).claim(
            JBClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: JBLeaf({index: 2, beneficiary: address(120), projectTokenCount: 5 ether, terminalTokenAmount: 5 ether}),
                proof: __proof
            })
        );
    }

    function _isRemotePeer(address) internal view virtual override returns (bool valid) {
        return false;
    }

    function _sendRootOverAMB(
        uint256 transportPayment,
        uint256 index,
        address token,
        uint256 amount,
        JBRemoteToken memory remoteToken,
        JBMessageRoot memory message
    )
        internal
        virtual
        override
    {}
    function peerChainId() external view override returns (uint256 chainId) {}
}

contract DeployerUnitTest is Test {
    function testDoesntRevert() public {
        // Deploy the deployer.
        JBOptimismSuckerDeployer _deployer = new JBOptimismSuckerDeployer(
            IJBDirectory(address(0)), IJBPermissions(address(0)), IJBTokens(address(0)), address(this), address(0)
        );

        // Configure the chain specific contstants.
        _deployer.setChainSpecificConstants(IOPMessenger(address(1)), IOPStandardBridge(address(1)));

        // Deploy the singleton.
        JBOptimismSucker _sucker = new JBOptimismSucker(
            _deployer,
            IJBDirectory(address(0)),
            IJBPermissions(address(0)),
            IJBTokens(address(0)),
            JBAddToBalanceMode.MANUAL,
            address(0)
        );

        // Configure the singleton on the deployer.
        _deployer.configureSingleton(_sucker);

        // Create a sucker for a project.
        _deployer.createForSender(1, bytes32(0));
    }
}
