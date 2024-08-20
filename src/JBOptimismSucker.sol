// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import {JBSucker} from "./JBSucker.sol";
import {JBOptimismSuckerDeployer} from "./deployers/JBOptimismSuckerDeployer.sol";
import {IJBOptimismSucker} from "./interfaces/IJBOptimismSucker.sol";
import {IJBSuckerDeployer} from "./interfaces/IJBSuckerDeployer.sol";
import {IOPMessenger} from "./interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "./interfaces/IOPStandardBridge.sol";
import {JBAddToBalanceMode} from "./enums/JBAddToBalanceMode.sol";
import {JBInboxTreeRoot} from "./structs/JBInboxTreeRoot.sol";
import {JBMessageRoot} from "./structs/JBMessageRoot.sol";
import {JBRemoteToken} from "./structs/JBRemoteToken.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

/// @notice A `JBSucker` implementation to suck tokens between two chains connected by an OP Bridge.
contract JBOptimismSucker is JBSucker, IJBOptimismSucker {
    using BitMaps for BitMaps.BitMap;
    using MerkleLib for MerkleLib.Tree;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBOptimismSucker_TokenNotMapped();
    error JBOptimismSucker_UnexpectedMsgValue();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The bridge used to bridge tokens between the local and remote chain.
    IOPStandardBridge public immutable override OPBRIDGE;

    /// @notice The messenger used to send messages between the local and remote sucker.
    IOPMessenger public immutable override OPMESSENGER;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory A contract storing directories of terminals and controllers for each project.    
    /// @param tokens A contract that manages token minting and burning.    
    /// @param permissions A contract storing permissions.
    /// @param peer The address of the peer sucker on the remote chain.
    /// @param atbMode The mode of adding tokens to balance.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        address peer,
        JBAddToBalanceMode atbMode
    ) JBSucker(directory, permissions, tokens, peer, atbMode, IJBSuckerDeployer(msg.sender).tempStoreId()) {
        // Fetch the messenger and bridge by doing a callback to the deployer contract.
        OPBRIDGE = JBOptimismSuckerDeployer(msg.sender).opBridge();
        OPMESSENGER = JBOptimismSuckerDeployer(msg.sender).opMessenger();
    }

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainID() external view virtual override returns (uint256) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return 10;
        if (chainId == 10) return 1;
        if (chainId == 11155111) return 11155420;
        if (chainId == 11155420) return 11155111;
        return 0;
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Checks if the `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal override returns (bool valid) {
        return sender == address(OPMESSENGER) && OPMESSENGER.xDomainMessageSender() == PEER;
    }

    /// @notice Use the `OPMESSENGER` to send the outbox tree for the `token` and the corresponding funds to the peer over the `OPBRIDGE`.
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(uint256 transportPayment, address token, JBRemoteToken memory remoteToken) internal override {
        uint256 nativeValue;

        // Revert if there's a `msg.value`. The OP bridge does not expect to be paid.
        if (transportPayment != 0) {
            revert JBOptimismSucker_UnexpectedMsgValue();
        }

        // Get the amount to send and then clear it from the outbox tree.
        uint256 amount = outbox[token].balance;
        delete outbox[token].balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox[token].nonce;

        // Ensure the token is mapped to an address on the remote chain.
        if (remoteToken.addr == address(0)) {
            revert JBOptimismSucker_TokenNotMapped();
        }

        // If the token is an ERC20, bridge it to the peer.
        if (token != JBConstants.NATIVE_TOKEN) {
            // Approve the tokens bing bridged.
            // slither-disable-next-line reentrancy-events
            SafeERC20.forceApprove(IERC20(token), address(OPBRIDGE), amount);

            // Bridge the tokens to the peer sucker.
            // slither-disable-next-line reentrency-events,calls-loop
            OPBRIDGE.bridgeERC20To({
                localToken: token,
                remoteToken: remoteToken.addr,
                to: PEER,
                amount: amount,
                minGasLimit: remoteToken.minGas,
                extraData: bytes("")
            });
        } else {
            // Otherwise, the token is the native token, and the amount will be sent as `msg.value`.
            nativeValue = amount;
        }

        bytes32 root = outbox[token].tree.root();
        uint256 index = outbox[token].tree.count - 1;

        // Send the message to the peer with the redeemed ETH.
        // slither-disable-next-line arbitrary-send-eth,reentrency-events,calls-loop
        OPMESSENGER.sendMessage{value: nativeValue}(
            PEER,
            abi.encodeCall(
                JBSucker.fromRemote,
                (
                    JBMessageRoot({
                        token: remoteToken.addr,
                        amount: amount,
                        remoteRoot: JBInboxTreeRoot({nonce: nonce, root: root})
                    })
                )
            ),
            MESSENGER_BASE_GAS_LIMIT
        );

        // Emit an event for the relayers to watch for.
        emit RootToRemote({root: root, token: token, index: index, nonce: nonce, caller: msg.sender});
    }
}
