// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBRulesets} from "@bananapus/core/src/interfaces/IJBRulesets.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import {JBSucker} from "./JBSucker.sol";
import {JBCCIPSuckerDeployer} from "./deployers/JBCCIPSuckerDeployer.sol";
import {JBAddToBalanceMode} from "./enums/JBAddToBalanceMode.sol";
import {ICCIPRouter, IWrappedNativeToken} from "./interfaces/ICCIPRouter.sol";
import {IJBCCIPSuckerDeployer} from "./interfaces/IJBCCIPSuckerDeployer.sol";
import {CCIPHelper} from "./libraries/CCIPHelper.sol";
import {JBInboxTreeRoot} from "./structs/JBInboxTreeRoot.sol";
import {JBMessageRoot} from "./structs/JBMessageRoot.sol";
import {JBRemoteToken} from "./structs/JBRemoteToken.sol";
import {JBTokenMapping} from "./structs/JBTokenMapping.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

/// @notice A `JBSucker` implementation to suck tokens between chains with Chainlink CCIP
contract JBCCIPSucker is JBSucker, IAny2EVMMessageReceiver {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBCCIPSucker_FailedToRefundFee();
    error JBCCIPSucker_InvalidRouter(address router);
    error JBCCIPSucker_UnexpectedAmountOfTokens(uint256 nOfTokens);

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    // TODO natspec
    ICCIPRouter public immutable CCIP_ROUTER;

    // TODO natspec
    uint256 public immutable REMOTE_CHAIN_ID;

    // TODO natspec
    uint64 public immutable REMOTE_CHAIN_SELECTOR;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param deployer A contract that deploys the clones for this contracts.
    /// @param directory A contract storing directories of terminals and controllers for each project.
    /// @param tokens A contract that manages token minting and burning.
    /// @param permissions A contract storing permissions.
    /// @param addToBalanceMode The mode of adding tokens to balance.
    constructor(
        JBCCIPSuckerDeployer deployer,
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        JBAddToBalanceMode addToBalanceMode,
        address trusted_forwarder
    )
        JBSucker(directory, permissions, tokens, addToBalanceMode, trusted_forwarder)
    {
        REMOTE_CHAIN_ID = IJBCCIPSuckerDeployer(deployer).ccipRemoteChainId();
        REMOTE_CHAIN_SELECTOR = IJBCCIPSuckerDeployer(deployer).ccipRemoteChainSelector();
        CCIP_ROUTER = IJBCCIPSuckerDeployer(deployer).ccipRouter();

        if (address(CCIP_ROUTER) == address(0)) revert JBCCIPSucker_InvalidRouter(address(CCIP_ROUTER));
    }

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainId() external view virtual override returns (uint256 chainId) {
        // Return the remote chain id
        return REMOTE_CHAIN_ID;
    }

    //*********************************************************************//
    // ------------------------- public views ---------------------------- //
    //*********************************************************************//

    /// @notice Return the current router
    /// @return CCIP router address
    function getRouter() public view returns (address) {
        return address(CCIP_ROUTER);
    }

    /// @notice IERC165 supports an interfaceId
    /// @param interfaceId The interfaceId to check
    /// @return true if the interfaceId is supported
    /// @dev Should indicate whether the contract implements IAny2EVMMessageReceiver
    /// e.g. return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId
    /// This allows CCIP to check if ccipReceive is available before calling it.
    /// If this returns false or reverts, only tokens are transferred to the receiver.
    /// If this returns true, tokens are transferred and ccipReceive is called atomically.
    /// Additionally, if the receiver address does not have code associated with
    /// it at the time of execution (EXTCODESIZE returns 0), only tokens will be transferred.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice The entrypoint for the CCIP router to call. This function should
    /// never revert, all errors should be handled internally in this contract.
    /// @param any2EvmMessage The message to process.
    /// @dev Extremely important to ensure only router calls this.
    function ccipReceive(Client.Any2EVMMessage calldata any2EvmMessage) external override {
        // only calls from the set router are accepted.
        if (_msgSender() != address(CCIP_ROUTER)) revert JBSucker_NotPeer(_msgSender());

        // Decode the message root from the peer
        JBMessageRoot memory root = abi.decode(any2EvmMessage.data, (JBMessageRoot));
        address origin = abi.decode(any2EvmMessage.sender, (address));

        // Make sure that the message came from our peer.
        if (origin != peer() || any2EvmMessage.sourceChainSelector != REMOTE_CHAIN_SELECTOR) {
            revert JBSucker_NotPeer(origin);
        }

        if (any2EvmMessage.destTokenAmounts.length != 1) {
            // This should never happen, we *always* send a tokenAmount.
            revert JBCCIPSucker_UnexpectedAmountOfTokens(any2EvmMessage.destTokenAmounts.length);
        }

        // As far as the sucker contract is aware wrapped natives are not a thing, it only handles ERC20s or native.
        Client.EVMTokenAmount memory tokenAmount = any2EvmMessage.destTokenAmounts[0];
        if (root.token == JBConstants.NATIVE_TOKEN) {
            // We can (safely) assume that the token that is set in the `destTokenAmounts` is a valid wrapped native.
            // If this ends up not being the case then our sanity check to see if we unwrapped the native asset will
            // fail.
            IWrappedNativeToken wrapped_native = IWrappedNativeToken(tokenAmount.token);
            uint256 balanceBefore = _balanceOf({token: JBConstants.NATIVE_TOKEN, addr: address(this)});

            // Withdraw the wrapped native asset.
            wrapped_native.withdraw(tokenAmount.amount);

            // Sanity check the unwrapping of the native asset.
            // slither-disable-next-line incorrect-equality
            assert(
                balanceBefore + tokenAmount.amount == _balanceOf({token: JBConstants.NATIVE_TOKEN, addr: address(this)})
            );
        }

        // Call ourselves to process the root.
        this.fromRemote(root);
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Unused in this context.
    function _isRemotePeer(address sender) internal view override returns (bool _valid) {
        // NOTICE: We do not check if its the `peer` here, as this contract is supposed to be the caller *NOT* the peer.
        return sender == address(this);
    }

    /// @notice
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRootOverAMB(
        uint256 transportPayment,
        uint256,
        address token,
        uint256 amount,
        JBRemoteToken memory remoteToken,
        JBMessageRoot memory sucker_message
    )
        internal
        override
    {
        // function _sendRoot(uint256 transportPayment, address token, JBRemoteToken memory remoteToken) internal
        // override {
        // Make sure we are attempting to pay the bridge
        if (transportPayment == 0) revert JBSucker_ExpectedMsgValue();

        // Wrap the token if it's native
        if (token == JBConstants.NATIVE_TOKEN) {
            // Get the wrapped native token.
            // slither-disable-next-line calls-loop
            IWrappedNativeToken wrapped_native = CCIP_ROUTER.getWrappedNative();
            // Deposit the wrapped native asset.
            // slither-disable-next-line calls-loop,arbitrary-send-eth
            wrapped_native.deposit{value: amount}();
            // Update the token to be the wrapped native asset.
            token = address(wrapped_native);
        }

        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(peer()),
            data: abi.encode(sucker_message),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: MESSENGER_BASE_GAS_LIMIT + remoteToken.minGas})
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees,
            // We pay in the native asset.
            feeToken: address(0)
        });

        // Get the fee required to send the CCIP message
        // slither-disable-next-line calls-loop
        uint256 fees = CCIP_ROUTER.getFee({destinationChainSelector: REMOTE_CHAIN_SELECTOR, message: message});

        if (fees > transportPayment) {
            revert JBSucker_InsufficientMsgValue(transportPayment, fees);
        }

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        SafeERC20.forceApprove(IERC20(token), address(CCIP_ROUTER), amount);

        // TODO: Handle this messageId- for later version with message retries
        // Send the message through the router and store the returned message ID
        /* messageId =  */
        // slither-disable-next-line calls-loop,unused-return
        CCIP_ROUTER.ccipSend{value: fees}({destinationChainSelector: REMOTE_CHAIN_SELECTOR, message: message});

        // Refund remaining balance.
        // slither-disable-next-line calls-loop,msg-value-loop
        (bool sent,) = _msgSender().call{value: msg.value - fees}("");
        if (!sent) revert JBCCIPSucker_FailedToRefundFee();
    }

    /// @notice Allow sucker implementations to add/override mapping rules to suite their specific needs.
    function _validateTokenMapping(JBTokenMapping calldata map) internal pure virtual override {
        // This sucker has an override since it could connect to a non-ETH chain, so we allow the `NATIVE_TOKEN` to map
        // to a token that is not the wrapped token on the remote.

        // Enforce a reasonable minimum gas limit for bridging. A minimum which is too low could lead to the loss of
        // funds.
        if (map.minGas < MESSENGER_ERC20_MIN_GAS_LIMIT && map.localToken != JBConstants.NATIVE_TOKEN) {
            revert JBSucker_BelowMinGas(map.minGas, MESSENGER_ERC20_MIN_GAS_LIMIT);
        }
    }
}
