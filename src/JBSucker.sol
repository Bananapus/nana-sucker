// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBCashOutTerminal} from "@bananapus/core/src/interfaces/IJBCashOutTerminal.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {JBAddToBalanceMode} from "./enums/JBAddToBalanceMode.sol";
import {IJBSucker} from "./interfaces/IJBSucker.sol";
import {IJBSuckerExtended} from "./interfaces/IJBSuckerExtended.sol";
import {IJBSuckerDeployer} from "./interfaces/IJBSuckerDeployer.sol";
import {JBClaim} from "./structs/JBClaim.sol";
import {JBInboxTreeRoot} from "./structs/JBInboxTreeRoot.sol";
import {JBMessageRoot} from "./structs/JBMessageRoot.sol";
import {JBOutboxTree} from "./structs/JBOutboxTree.sol";
import {JBRemoteToken} from "./structs/JBRemoteToken.sol";
import {JBTokenMapping} from "./structs/JBTokenMapping.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";
import {JBSuckerState} from "./enums/JBSuckerState.sol";

/// @notice An abstract contract for bridging a Juicebox project's tokens and the corresponding funds to and from a
/// remote chain.
/// @dev Beneficiaries and balances are tracked on two merkle trees: the outbox tree is used to send from the local
/// chain to the remote chain, and the inbox tree is used to receive from the remote chain to the local chain.
/// @dev Throughout this contract, "terminal token" refers to any token accepted by a project's terminal.
/// @dev This contract does *NOT* support tokens that have a fee on regular transfers and rebasing tokens.
abstract contract JBSucker is ERC2771Context, JBPermissioned, Initializable, ERC165, IJBSuckerExtended {
    using BitMaps for BitMaps.BitMap;
    using MerkleLib for MerkleLib.Tree;
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBSucker_BelowMinGas(uint256 minGas, uint256 minGasLimit);
    error JBSucker_InsufficientBalance(uint256 amount, uint256 balance);
    error JBSucker_InvalidNativeRemoteAddress(address remoteToken);
    error JBSucker_InvalidProof(bytes32 root, bytes32 inboxRoot);
    error JBSucker_LeafAlreadyExecuted(address token, uint256 index);
    error JBSucker_ManualNotAllowed(JBAddToBalanceMode mode);
    error JBSucker_DeprecationTimestampTooSoon(uint256 givenTime, uint256 minimumTime);
    error JBSucker_NoTerminalForToken(uint256 projectId, address token);
    error JBSucker_NotPeer(address caller);
    error JBSucker_QueueInsufficientSize(uint256 amount, uint256 minimumAmount);
    error JBSucker_TokenNotMapped(address token);
    error JBSucker_TokenHasInvalidEmergencyHatchState(address token);
    error JBSucker_TokenAlreadyMapped(address localToken, address mappedTo);
    error JBSucker_UnexpectedMsgValue(uint256 value);
    error JBSucker_ExpectedMsgValue();
    error JBSucker_InsufficientMsgValue(uint256 received, uint256 expected);
    error JBSucker_ZeroBeneficiary();
    error JBSucker_ZeroERC20Token();
    error JBSucker_Deprecated();

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice A reasonable minimum gas limit for a basic cross-chain call. The minimum amount of gas required to call
    /// the `fromRemote` (successfully/safely) on the remote chain.
    uint32 public constant override MESSENGER_BASE_GAS_LIMIT = 300_000;

    /// @notice A reasonable minimum gas limit used when bridging ERC-20s. The minimum amount of gas required to
    /// (successfully/safely) perform a transfer on the remote chain.
    uint32 public constant override MESSENGER_ERC20_MIN_GAS_LIMIT = 200_000;

    //*********************************************************************//
    // ------------------------- internal constants ----------------------- //
    //*********************************************************************//

    /// @notice The depth of the merkle tree used to store the outbox and inbox.
    uint32 constant _TREE_DEPTH = 32;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice Whether the `amountToAddToBalance` gets added to the project's balance automatically when `claim` is
    /// called or manually by calling `addOutstandingAmountToBalance`.
    JBAddToBalanceMode public immutable override ADD_TO_BALANCE_MODE;

    /// @notice The address of this contract's deployer.
    address public immutable override DEPLOYER;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The contract that manages token minting and burning.
    IJBTokens public immutable override TOKENS;

    //*********************************************************************//
    // --------------------- private stored properties ------------------- //
    //*********************************************************************//

    /// @notice The timestamp after which the sucker is entirely deprecated.
    uint256 internal _deprecatedAfter;

    /// @notice The ID of the project (on the local chain) that this sucker is associated with.
    uint256 private _localProjectId;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice Tracks whether individual leaves in a given token's merkle tree have been executed (to prevent
    /// double-spending).
    /// @dev A leaf is "executed" when the tokens it represents are minted for its beneficiary.
    /// @custom:param token The token to get the executed bitmap of.
    mapping(address token => BitMaps.BitMap) internal _executedFor;

    /// @notice The inbox merkle tree root for a given token.
    /// @custom:param token The local terminal token to get the inbox for.
    mapping(address token => JBInboxTreeRoot root) internal _inboxOf;

    /// @notice The outbox merkle tree for a given token.
    /// @custom:param token The local terminal token to get the outbox for.
    mapping(address token => JBOutboxTree) internal _outboxOf;

    /// @notice Information about the token on the remote chain that the given token on the local chain is mapped to.
    /// @custom:param token The local terminal token to get the remote token for.
    mapping(address token => JBRemoteToken remoteToken) internal _remoteTokenFor;

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice The outstanding amount of tokens to be added to the project's balance by `claim` or
    /// `addOutstandingAmountToBalance`.
    /// @param token The local terminal token to get the amount to add to balance for.
    function amountToAddToBalanceOf(address token) public view override returns (uint256) {
        // Get the amount that is in this sucker to be bridged.
        return _balanceOf(token, address(this)) - _outboxOf[token].balance;
    }

    /// @notice The inbox merkle tree root for a given token.
    /// @param token The local terminal token to get the inbox for.
    function inboxOf(address token) external view returns (JBInboxTreeRoot memory) {
        return _inboxOf[token];
    }

    /// @notice Checks whether the specified token is mapped to a remote token.
    /// @param token The terminal token to check.
    /// @return A boolean which is `true` if the token is mapped to a remote token and `false` if it is not.
    function isMapped(address token) external view override returns (bool) {
        return _remoteTokenFor[token].addr != address(0);
    }

    /// @notice Information about the token on the remote chain that the given token on the local chain is mapped to.
    /// @param token The local terminal token to get the remote token for.
    function outboxOf(address token) external view returns (JBOutboxTree memory) {
        return _outboxOf[token];
    }

    /// @notice Returns the chain on which the peer is located.
    /// @return chain ID of the peer.
    function peerChainId() external view virtual returns (uint256);

    /// @notice Information about the token on the remote chain that the given token on the local chain is mapped to.
    /// @param token The local terminal token to get the remote token for.
    function remoteTokenFor(address token) external view returns (JBRemoteToken memory) {
        return _remoteTokenFor[token];
    }

    //*********************************************************************//
    // ------------------------- public views ---------------------------- //
    //*********************************************************************//

    /// @notice The peer sucker on the remote chain.
    function peer() public view virtual returns (address) {
        /// This can be overridden by the inheriting contract to return a different address. This is fully supported by
        /// the sucker implementation and all its off-chain infrastructure, This does however break some
        /// invariants/assumptions, for revnets it would break the assumption of matching configurations on both chains,
        /// for this reason we only support a matching address.

        // The peer is at the same address on the other chain.
        return address(this);
    }

    /// @notice The ID of the project (on the local chain) that this sucker is associated with.
    function projectId() public view returns (uint256) {
        return _localProjectId;
    }

    /// @notice Reports the deprecation state of the sucker.
    /// @return state The current deprecation state
    function state() public view override returns (JBSuckerState) {
        uint256 __deprecatedAfter = _deprecatedAfter;

        // The sucker is fully functional, no deprecation has been set yet.
        if (__deprecatedAfter == 0) {
            return JBSuckerState.ENABLED;
        }

        // The sucker will soon be considered deprecated, this functions only as a warning to users.
        if (block.timestamp < __deprecatedAfter - _maxMessagingDelay()) {
            return JBSuckerState.DEPRECATION_PENDING;
        }

        // The sucker will no longer send new roots to the pair, but it will accept new incoming roots.
        if (block.timestamp < __deprecatedAfter) {
            return JBSuckerState.SENDING_DISABLED;
        }

        // The sucker is now in the final state of deprecation. It will no longer allow new roots and if needed it will
        // let users emergency exit.
        return JBSuckerState.DEPRECATED;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IJBSuckerExtended).interfaceId || interfaceId == type(IJBSucker).interfaceId
            || interfaceId == type(IJBPermissioned).interfaceId || super.supportsInterface(interfaceId);
    }

    //*********************************************************************//
    // ------------------------ internal views --------------------------- //
    //*********************************************************************//

    /// @notice Helper to get the `addr`'s balance for a given `token`.
    /// @param token The token to get the balance for.
    /// @param addr The address to get the `token` balance of.
    /// @return balance The address' `token` balance.
    function _balanceOf(address token, address addr) internal view returns (uint256 balance) {
        if (token == JBConstants.NATIVE_TOKEN) {
            return addr.balance;
        }

        // slither-disable-next-line calls-loop
        return IERC20(token).balanceOf(addr);
    }

    /// @notice Builds a hash as they are stored in the merkle tree.
    /// @param projectTokenCount The number of project tokens being cashed out.
    /// @param terminalTokenAmount The amount of terminal tokens being reclaimed by the cash out.
    /// @param beneficiary The beneficiary which will receive the project tokens.
    function _buildTreeHash(
        uint256 projectTokenCount,
        uint256 terminalTokenAmount,
        address beneficiary
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(projectTokenCount, terminalTokenAmount, beneficiary));
    }

    /// @notice Allow sucker implementations to add/override mapping rules to suite their specific needs.
    function _validateTokenMapping(JBTokenMapping calldata map) internal pure virtual {
        bool isNative = map.localToken == JBConstants.NATIVE_TOKEN;

        // If the token being mapped is the native token, the `remoteToken` must also be the native token.
        // The native token can also be mapped to the 0 address, which is used to disable native token bridging.
        if (isNative && map.remoteToken != JBConstants.NATIVE_TOKEN && map.remoteToken != address(0)) {
            revert JBSucker_InvalidNativeRemoteAddress(map.remoteToken);
        }

        // Enforce a reasonable minimum gas limit for bridging. A minimum which is too low could lead to the loss of
        // funds.
        if (map.minGas < MESSENGER_ERC20_MIN_GAS_LIMIT && !isNative) {
            revert JBSucker_BelowMinGas(map.minGas, MESSENGER_ERC20_MIN_GAS_LIMIT);
        }
    }

    /// @notice The calldata. Preferred to use over `msg.data`.
    /// @return calldata The `msg.data` of this call.
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice The message's sender. Preferred to use over `msg.sender`.
    /// @return sender The address which sent this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    /// @dev ERC-2771 specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view virtual override(ERC2771Context, Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory A contract storing directories of terminals and controllers for each project.
    /// @param permissions A contract storing permissions.
    /// @param tokens A contract that manages token minting and burning.
    /// @param addToBalanceMode The mode of adding tokens to balance.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        JBAddToBalanceMode addToBalanceMode,
        address trusted_forwarder
    )
        ERC2771Context(trusted_forwarder)
        JBPermissioned(permissions)
    {
        DIRECTORY = directory;
        TOKENS = tokens;
        DEPLOYER = msg.sender;
        ADD_TO_BALANCE_MODE = addToBalanceMode;

        // Make it so the singleton can't be initialized.
        _disableInitializers();

        // Sanity check: make sure the merkle lib uses the same tree depth.
        assert(MerkleLib.TREE_DEPTH == _TREE_DEPTH);
    }

    /// @notice Initializes the sucker with the project ID and peer address.
    /// @param __projectId The ID of the project (on the local chain) that this sucker is associated with.
    function initialize(uint256 __projectId) public initializer {
        // slither-disable-next-line missing-zero-check
        _localProjectId = __projectId;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Adds the reclaimed `token` balance to the projects terminal. Can only be used if `ADD_TO_BALANCE_MODE`
    /// is
    /// `MANUAL`.
    /// @param token The address of the terminal token to add to the project's balance.
    function addOutstandingAmountToBalance(address token) external override {
        if (ADD_TO_BALANCE_MODE != JBAddToBalanceMode.MANUAL) {
            revert JBSucker_ManualNotAllowed(ADD_TO_BALANCE_MODE);
        }

        // Add entire outstanding amount to the project's balance.
        _addToBalance({token: token, amount: amountToAddToBalanceOf(token)});
    }

    /// @notice Performs multiple claims.
    /// @param claims A list of claims to perform (including the terminal token, merkle tree leaf, and proof for each
    /// claim).
    function claim(JBClaim[] calldata claims) external override {
        // Claim each.
        for (uint256 i; i < claims.length; i++) {
            claim(claims[i]);
        }
    }

    /// @notice `JBClaim` project tokens which have been bridged from the remote chain for their beneficiary.
    /// @param claimData The terminal token, merkle tree leaf, and proof for the claim.
    function claim(JBClaim calldata claimData) public override {
        // Attempt to validate the proof against the inbox tree for the terminal token.
        _validate({
            projectTokenCount: claimData.leaf.projectTokenCount,
            terminalToken: claimData.token,
            terminalTokenAmount: claimData.leaf.terminalTokenAmount,
            beneficiary: claimData.leaf.beneficiary,
            index: claimData.leaf.index,
            leaves: claimData.proof
        });

        emit Claimed({
            beneficiary: claimData.leaf.beneficiary,
            token: claimData.token,
            projectTokenCount: claimData.leaf.projectTokenCount,
            terminalTokenAmount: claimData.leaf.terminalTokenAmount,
            index: claimData.leaf.index,
            autoAddedToBalance: ADD_TO_BALANCE_MODE == JBAddToBalanceMode.ON_CLAIM ? true : false,
            caller: _msgSender()
        });

        // Give the user their project tokens, send the project its funds.
        _handleClaim({
            terminalToken: claimData.token,
            terminalTokenAmount: claimData.leaf.terminalTokenAmount,
            projectTokenAmount: claimData.leaf.projectTokenCount,
            beneficiary: claimData.leaf.beneficiary
        });
    }

    /// @notice Receive a merkle root for a terminal token from the remote project.
    /// @dev This can only be called by the messenger contract on the local chain, with a message from the remote peer.
    /// @param root The merkle root, token, and amount being received.
    function fromRemote(JBMessageRoot calldata root) external payable {
        // Make sure that the message came from our peer.
        if (!_isRemotePeer(_msgSender())) {
            revert JBSucker_NotPeer(_msgSender());
        }

        // Get the inbox in storage.
        JBInboxTreeRoot storage inbox = _inboxOf[root.token];

        // If the received tree's nonce is greater than the current inbox tree's nonce, update the inbox tree.
        // We can't revert because this could be a native token transfer. If we reverted, we would lose the native
        // tokens.
        if (root.remoteRoot.nonce > inbox.nonce && state() != JBSuckerState.DEPRECATED) {
            inbox.nonce = root.remoteRoot.nonce;
            inbox.root = root.remoteRoot.root;
            emit NewInboxTreeRoot({
                token: root.token,
                nonce: root.remoteRoot.nonce,
                root: root.remoteRoot.root,
                caller: _msgSender()
            });
        }
    }

    /// @notice Map an ERC-20 token on the local chain to an ERC-20 token on the remote chain, allowing that token to be
    /// bridged.
    /// @param map The local and remote terminal token addresses to map, and minimum amount/gas limits for bridging
    /// them.
    function mapToken(JBTokenMapping calldata map) public payable override {
        _mapToken({map: map, transportPaymentValue: msg.value});
    }

    /// @notice Map multiple ERC-20 tokens on the local chain to ERC-20 tokens on the remote chain, allowing those
    /// tokens to be bridged.
    /// @param maps A list of local and remote terminal token addresses to map, and minimum amount/gas limits for
    /// bridging them.
    function mapTokens(JBTokenMapping[] calldata maps) external payable override {
        uint256 numberToDisable;

        // Loop over the number of mappings and increase numberToDisable to correctly set transportPaymentValue.
        for (uint256 h; h < maps.length; h++) {
            if (maps[h].remoteToken == address(0) && _outboxOf[maps[h].localToken].balance != 0) {
                numberToDisable++;
            }
        }

        // Perform each token mapping.
        for (uint256 i; i < maps.length; i++) {
            // slither-disable-next-line msg-value-loop
            _mapToken({map: maps[i], transportPaymentValue: numberToDisable > 0 ? msg.value / numberToDisable : 0});
        }
    }

    /// @notice Enables the emergency hatch for a list of tokens, allowing users to exit on the chain they deposited on.
    /// @dev For use when a token or a few tokens are no longer compatible with a bridge.
    /// @param tokens The terminal tokens to enable the emergency hatch for.
    function enableEmergencyHatchFor(address[] calldata tokens) external override {
        // The caller must be the project owner or have the `QUEUE_RULESETS` permission from them.
        // slither-disable-next-line calls-loop
        uint256 _projectId = projectId();

        _requirePermissionFrom({
            account: DIRECTORY.PROJECTS().ownerOf(_projectId),
            projectId: _projectId,
            permissionId: JBPermissionIds.SUCKER_SAFETY
        });

        // Enable the emergency hatch for each token.
        for (uint256 i; i < tokens.length; i++) {
            // We have an invariant where if emergencyHatch is true, enabled should be false.
            _remoteTokenFor[tokens[i]].enabled = false;
            _remoteTokenFor[tokens[i]].emergencyHatch = true;
        }

        emit EmergencyHatchOpened(tokens, _msgSender());
    }

    /// @notice Prepare project tokens and the cash out amount backing them to be bridged to the remote chain.
    /// @dev This adds the tokens and funds to the outbox tree for the `token`. They will be bridged by the next call to
    /// `toRemote` for the same `token`.
    /// @param projectTokenCount The number of project tokens to prepare for bridging.
    /// @param beneficiary The address of the recipient of the tokens on the remote chain.
    /// @param minTokensReclaimed The minimum amount of terminal tokens to cash out for. If the amount cashed out is
    /// less
    /// than this, the transaction will revert.
    /// @param token The address of the terminal token to cash out for.
    function prepare(
        uint256 projectTokenCount,
        address beneficiary,
        uint256 minTokensReclaimed,
        address token
    )
        external
        override
    {
        // Make sure the beneficiary is not the zero address, as this would revert when minting on the remote chain.
        if (beneficiary == address(0)) {
            revert JBSucker_ZeroBeneficiary();
        }

        // Get the project's token.
        IERC20 projectToken = IERC20(address(TOKENS.tokenOf(projectId())));
        if (address(projectToken) == address(0)) {
            revert JBSucker_ZeroERC20Token();
        }

        // Make sure that the token is mapped to a remote token.
        if (!_remoteTokenFor[token].enabled) {
            revert JBSucker_TokenNotMapped(token);
        }

        // Make sure that the sucker still allows sending new messaged.
        JBSuckerState deprecationState = state();
        if (deprecationState == JBSuckerState.DEPRECATED || deprecationState == JBSuckerState.SENDING_DISABLED) {
            revert JBSucker_Deprecated();
        }

        // Transfer the tokens to this contract.
        // slither-disable-next-line reentrancy-events,reentrancy-benign
        projectToken.safeTransferFrom({from: _msgSender(), to: address(this), value: projectTokenCount});

        // Cash out the tokens.
        // slither-disable-next-line reentrancy-events,reentrancy-benign
        uint256 terminalTokenAmount = _pullBackingAssets({
            projectToken: projectToken,
            count: projectTokenCount,
            token: token,
            minTokensReclaimed: minTokensReclaimed
        });

        // Insert the item into the outbox tree for the terminal `token`.
        _insertIntoTree({
            projectTokenCount: projectTokenCount,
            token: token,
            terminalTokenAmount: terminalTokenAmount,
            beneficiary: beneficiary
        });
    }

    /// @notice Bridge the project tokens, cashed out funds, and beneficiary information for a given `token` to the
    /// remote
    /// chain.
    /// @dev This sends the outbox root for the specified `token` to the remote chain.
    /// @param token The terminal token being bridged.
    function toRemote(address token) external payable override {
        JBRemoteToken memory remoteToken = _remoteTokenFor[token];

        // Ensure that the amount being bridged exceeds the minimum bridge amount.
        if (_outboxOf[token].balance < remoteToken.minBridgeAmount) {
            revert JBSucker_QueueInsufficientSize(_outboxOf[token].balance, remoteToken.minBridgeAmount);
        }

        // Send the merkle root to the remote chain.
        _sendRoot({transportPayment: msg.value, token: token, remoteToken: remoteToken});
    }

    /// @notice Lets user exit on the chain they deposited in a scenario where the bridge is no longer functional.
    /// @param claimData The terminal token, merkle tree leaf, and proof for the claim
    function exitThroughEmergencyHatch(JBClaim calldata claimData) external override {
        // Does all the needed validation to ensure that the claim is valid *and* that claiming through the emergency
        // hatch is allowed.
        _validateForEmergencyExit({
            projectTokenCount: claimData.leaf.projectTokenCount,
            terminalToken: claimData.token,
            terminalTokenAmount: claimData.leaf.terminalTokenAmount,
            beneficiary: claimData.leaf.beneficiary,
            index: claimData.leaf.index,
            leaves: claimData.proof
        });

        // Decrease the outstanding balance for this token.
        _outboxOf[claimData.token].balance -= claimData.leaf.terminalTokenAmount;

        // Give the user their project tokens, send the project its funds.
        _handleClaim({
            terminalToken: claimData.token,
            terminalTokenAmount: claimData.leaf.terminalTokenAmount,
            projectTokenAmount: claimData.leaf.projectTokenCount,
            beneficiary: claimData.leaf.beneficiary
        });
    }

    /// @notice Set or remove the time after which this sucker will be deprecated, once deprecated the sucker will no
    /// longer be functional and it will let all users exit.
    /// @param timestamp The time after which the sucker will be deprecated. Or `0` to remove the upcoming deprecation.
    function setDeprecation(uint40 timestamp) external override {
        // As long as the sucker has not reached the final deprecation state its deprecation time can be
        // extended/shortened.
        if (state() == JBSuckerState.DEPRECATED) revert JBSucker_Deprecated();

        // slither-disable-next-line calls-loop
        uint256 _projectId = projectId();

        _requirePermissionFrom({
            account: DIRECTORY.PROJECTS().ownerOf(_projectId),
            projectId: _projectId,
            permissionId: JBPermissionIds.SUCKER_SAFETY
        });

        // This is the earliest time for when the sucker can be considered deprecated.
        // There is a mandatory delay to allow for remaining messages to be received.
        // This should be called on both sides of the suckers, preferably with a matching timestamp.
        uint256 nextEarliestDeprecationTime = block.timestamp + _maxMessagingDelay();

        // The deprecation can be entirely disabled *or* it has to be later than the earliest possible time.
        if (timestamp != 0 && timestamp < nextEarliestDeprecationTime) {
            revert JBSucker_DeprecationTimestampTooSoon(timestamp, nextEarliestDeprecationTime);
        }

        _deprecatedAfter = timestamp;
        emit DeprecationTimeUpdated(timestamp, _msgSender());
    }

    //*********************************************************************//
    // ---------------------------- receive  ----------------------------- //
    //*********************************************************************//

    /// @notice Used to receive cashed out native tokens.
    receive() external payable {}

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Adds funds to the projects balance.
    /// @param token The terminal token to add to the project's balance.
    /// @param amount The amount of terminal tokens to add to the project's balance.
    function _addToBalance(address token, uint256 amount) internal {
        // Make sure that the current `amountToAddToBalance` is greater than or equal to the amount being added.
        uint256 addableAmount = amountToAddToBalanceOf(token);
        if (amount > addableAmount) {
            revert JBSucker_InsufficientBalance(amount, addableAmount);
        }

        uint256 _projectId = projectId();

        // Get the project's primary terminal for the token.
        // slither
        // slither-disable-next-line calls-loop
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf({projectId: _projectId, token: token});

        // slither-disable-next-line incorrect-equality
        if (address(terminal) == address(0)) revert JBSucker_NoTerminalForToken(_projectId, token);

        // Perform the `addToBalance`.
        if (token != JBConstants.NATIVE_TOKEN) {
            // slither-disable-next-line calls-loop
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));

            SafeERC20.forceApprove({token: IERC20(token), spender: address(terminal), value: amount});

            // slither-disable-next-line calls-loop
            terminal.addToBalanceOf({
                projectId: _projectId,
                token: token,
                amount: amount,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: ""
            });

            // Sanity check: make sure we transfer the full amount.
            // slither-disable-next-line calls-loop,incorrect-equality
            assert(IERC20(token).balanceOf(address(this)) == balanceBefore - amount);
        } else {
            // If the token is the native token, use `msg.value`.
            // slither-disable-next-line arbitrary-send-eth,calls-loop
            terminal.addToBalanceOf{value: amount}({
                projectId: _projectId,
                token: token,
                amount: amount,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: ""
            });
        }
    }

    /// @notice The action(s) to perform after a user has succesfully proven their claim.
    /// @param terminalToken The terminal token being sucked.
    /// @param terminalTokenAmount The amount of terminal tokens.
    /// @param projectTokenAmount The amount of project tokens.
    /// @param beneficiary The beneficiary of the project tokens.
    function _handleClaim(
        address terminalToken,
        uint256 terminalTokenAmount,
        uint256 projectTokenAmount,
        address beneficiary
    )
        internal
    {
        // If this contract's add to balance mode is `ON_CLAIM`, add the cashed out funds to the project's balance.
        if (ADD_TO_BALANCE_MODE == JBAddToBalanceMode.ON_CLAIM) {
            _addToBalance({token: terminalToken, amount: terminalTokenAmount});
        }

        uint256 _projectId = projectId();

        // Mint the project tokens for the beneficiary.
        // slither-disable-next-line calls-loop,unused-return
        IJBController(address(DIRECTORY.controllerOf(_projectId))).mintTokensOf({
            projectId: _projectId,
            tokenCount: projectTokenAmount,
            beneficiary: beneficiary,
            memo: "",
            useReservedPercent: false
        });
    }

    /// @notice Inserts a new leaf into the outbox merkle tree for the specified `token`.
    /// @param projectTokenCount The amount of project tokens being cashed out.
    /// @param token The terminal token being cashed out for.
    /// @param terminalTokenAmount The amount of terminal tokens reclaimed by cashing out.
    /// @param beneficiary The beneficiary of the project tokens on the remote chain.
    function _insertIntoTree(
        uint256 projectTokenCount,
        address token,
        uint256 terminalTokenAmount,
        address beneficiary
    )
        internal
    {
        // Build a hash based on the token amounts and the beneficiary.
        bytes32 hashed = _buildTreeHash({
            projectTokenCount: projectTokenCount,
            terminalTokenAmount: terminalTokenAmount,
            beneficiary: beneficiary
        });

        // Get the outbox in storage.
        JBOutboxTree storage outbox = _outboxOf[token];

        // Create a new tree based on the outbox tree for the terminal token with the hash inserted.
        MerkleLib.Tree memory tree = outbox.tree.insert(hashed);

        // Update the outbox tree and balance for the terminal token.
        outbox.tree = tree;
        outbox.balance += terminalTokenAmount;

        emit InsertToOutboxTree({
            beneficiary: beneficiary,
            token: token,
            hashed: hashed,
            index: tree.count - 1, // Subtract 1 since we want the 0-based index.
            root: outbox.tree.root(),
            projectTokenCount: projectTokenCount,
            terminalTokenAmount: terminalTokenAmount,
            caller: _msgSender()
        });
    }

    /// @notice Checks if the `sender` (`_msgSender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal virtual returns (bool valid);

    /// @notice Map an ERC-20 token on the local chain to an ERC-20 token on the remote chain, allowing that token to be
    /// bridged or disabled.
    /// @param map The local and remote terminal token addresses to map, and minimum amount/gas limits for bridging
    /// them.
    /// @param transportPaymentValue The amount of `msg.value` to send for the token mapping.
    function _mapToken(JBTokenMapping calldata map, uint256 transportPaymentValue) internal {
        address token = map.localToken;
        JBRemoteToken memory currentMapping = _remoteTokenFor[token];

        // Once the emergency hatch for a token is enabled it can't be disabled.
        if (currentMapping.emergencyHatch) {
            revert JBSucker_TokenHasInvalidEmergencyHatchState(token);
        }

        // Validate the token mapping according to the rules of the sucker.
        _validateTokenMapping(map);

        // Reference the project id.
        uint256 _projectId = projectId();

        // slither-disable-next-line calls-loop
        _requirePermissionFrom({
            account: DIRECTORY.PROJECTS().ownerOf(_projectId),
            projectId: _projectId,
            permissionId: JBPermissionIds.MAP_SUCKER_TOKEN
        });

        // Make sure that the token does not get remapped to another remote token.
        // As this would cause the funds for this token to be double spendable on the other side.
        // It should not be possible to cause any issues even without this check
        // a bridge *should* never accept such a request. This is mostly a sanity check.
        if (
            currentMapping.addr != address(0) && currentMapping.addr != map.remoteToken && map.remoteToken != address(0)
                && _outboxOf[token].tree.count != 0
        ) {
            revert JBSucker_TokenAlreadyMapped(token, currentMapping.addr);
        }

        // If the remote token is being set to the 0 address (which disables bridging), send any remaining outbox funds
        // to the remote chain.
        if (map.remoteToken == address(0) && _outboxOf[token].balance != 0) {
            _sendRoot({transportPayment: transportPaymentValue, token: token, remoteToken: currentMapping});
        }

        // Update the token mapping.
        _remoteTokenFor[token] = JBRemoteToken({
            enabled: map.remoteToken != address(0),
            emergencyHatch: false,
            minGas: map.minGas,
            // This is done so that a token can be disabled and then enabled again
            // while ensuring the remoteToken never changes (unless it hasn't been used yet)
            addr: map.remoteToken == address(0) ? currentMapping.addr : map.remoteToken,
            minBridgeAmount: map.minBridgeAmount
        });
    }

    /// @notice Cash out project tokens for terminal tokens.
    /// @param projectToken The project token being cashed out.
    /// @param count The number of project tokens to cash out.
    /// @param token The terminal token to cash out for.
    /// @param minTokensReclaimed The minimum amount of terminal tokens to reclaim. If the amount reclaimed is less than
    /// this, the transaction will revert.
    /// @return reclaimedAmount The amount of terminal tokens reclaimed by the cash out.
    function _pullBackingAssets(
        IERC20 projectToken,
        uint256 count,
        address token,
        uint256 minTokensReclaimed
    )
        internal
        virtual
        returns (uint256 reclaimedAmount)
    {
        projectToken;

        uint256 _projectId = projectId();

        // Get the project's primary terminal for `token`. We will cash out from this terminal.
        IJBCashOutTerminal terminal =
            IJBCashOutTerminal(address(DIRECTORY.primaryTerminalOf({projectId: _projectId, token: token})));

        // If the project doesn't have a primary terminal for `token`, revert.
        if (address(terminal) == address(0)) {
            revert JBSucker_NoTerminalForToken(_projectId, token);
        }

        // Cash out the tokens.
        uint256 balanceBefore = _balanceOf(token, address(this));
        reclaimedAmount = terminal.cashOutTokensOf({
            holder: address(this),
            projectId: _projectId,
            cashOutCount: count,
            tokenToReclaim: token,
            minTokensReclaimed: minTokensReclaimed,
            beneficiary: payable(address(this)),
            metadata: bytes("")
        });

        // Sanity check to make sure we received the expected amount.
        // This prevents malicious terminals from reporting amounts other than what they send.
        // slither-disable-next-line incorrect-equality
        assert(reclaimedAmount == _balanceOf({token: token, addr: address(this)}) - balanceBefore);
    }

    /// @notice Send the outbox root for the specified token to the remote peer.
    /// @dev The call may have a `transportPayment` for bridging native tokens. Require it to be `0` if it is not
    /// needed. Make sure if a value being paid to the bridge is expected to revert if the given value is `0`.
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message. (usually
    /// derived from `msg.value`)
    /// @param token The terminal token to bridge the merkle tree of.
    /// @param remoteToken The remote token which the `token` is mapped to.
    function _sendRoot(uint256 transportPayment, address token, JBRemoteToken memory remoteToken) internal virtual {
        // Ensure the token is mapped to an address on the remote chain.
        if (remoteToken.addr == address(0)) revert JBSucker_TokenNotMapped(token);

        // Make sure that the sucker still allows sending new messaged.
        JBSuckerState deprecationState = state();
        if (deprecationState == JBSuckerState.DEPRECATED || deprecationState == JBSuckerState.SENDING_DISABLED) {
            revert JBSucker_Deprecated();
        }

        // Get the outbox in storage.
        JBOutboxTree storage outbox = _outboxOf[token];

        // Get the amount to send and then clear it from the outbox tree.
        uint256 amount = outbox.balance;
        delete outbox.balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox.nonce;
        bytes32 root = outbox.tree.root();

        uint256 count = outbox.tree.count;
        // Update the numberOfClaimsSent to the current count of the tree.
        // This is used as in the fallback to allow users to withdraw locally if the bridge is reverting.
        outbox.numberOfClaimsSent = count;
        uint256 index = count - 1;

        // Emit an event for the relayers to watch for.
        emit RootToRemote({root: root, token: token, index: index, nonce: nonce, caller: _msgSender()});

        // Build the message to be send.
        JBMessageRoot memory message = JBMessageRoot({
            token: remoteToken.addr,
            amount: amount,
            remoteRoot: JBInboxTreeRoot({nonce: nonce, root: root})
        });

        // Execute the chain/sucker specific logic for transferring the assets and communicating the root.
        _sendRootOverAMB(transportPayment, index, token, amount, remoteToken, message);
    }

    /// @notice Performs the logic to send a message to the peer over the AMB.
    /// @dev This is chain/sucker/bridge specific logic.
    /// @param transportPayment The amount of `msg.value` that is going to get paid for sending this message.
    /// @param index The index of the most recent message that is part of the root.
    /// @param token The terminal token being bridged.
    /// @param amount The amount of terminal tokens being bridged.
    /// @param remoteToken The remote token which the terminal token is mapped to.
    /// @param message The message/root to send to the remote chain.
    function _sendRootOverAMB(
        uint256 transportPayment,
        uint256 index,
        address token,
        uint256 amount,
        JBRemoteToken memory remoteToken,
        JBMessageRoot memory message
    )
        internal
        virtual;

    /// @notice What is the maximum time it takes for a message to be received on the other side.
    /// @dev Be sure to keep in mind if a message fails having to retry and the time it takes to retry.
    /// @return The maximum time it takes for a message to be received on the other side.
    function _maxMessagingDelay() internal pure virtual returns (uint40) {
        return 14 days;
    }

    /// @notice Validates a leaf as being in the inbox merkle tree and registers the leaf as executed (to prevent
    /// double-spending).
    /// @dev Reverts if the leaf is invalid.
    /// @param projectTokenCount The number of project tokens which were cashed out.
    /// @param terminalToken The terminal token that the project tokens were cashed out for.
    /// @param terminalTokenAmount The amount of terminal tokens reclaimed by the cash out.
    /// @param beneficiary The beneficiary which will receive the project tokens.
    /// @param index The index of the leaf being proved in the terminal token's inbox tree.
    /// @param leaves The leaves that prove that the leaf at the `index` is in the tree (i.e. the merkle branch that the
    /// leaf is on).
    function _validate(
        uint256 projectTokenCount,
        address terminalToken,
        uint256 terminalTokenAmount,
        address beneficiary,
        uint256 index,
        bytes32[_TREE_DEPTH] calldata leaves
    )
        internal
    {
        // Make sure the leaf has not already been executed.
        if (_executedFor[terminalToken].get(index)) {
            revert JBSucker_LeafAlreadyExecuted(terminalToken, index);
        }

        // Register the leaf as executed to prevent double-spending.
        _executedFor[terminalToken].set(index);

        // Calculate the root based on the leaf, the branch, and the index.
        // Compare to the current root, Revert if they do not match.
        _validateBranchRoot(
            _inboxOf[terminalToken].root, projectTokenCount, terminalTokenAmount, beneficiary, index, leaves
        );
    }

    /// @notice Validates a leaf as being in the outbox merkle tree and not being send over the amb, and registers the
    /// leaf as executed (to prevent double-spending).
    /// @dev Reverts if the leaf is invalid.
    /// @param projectTokenCount The number of project tokens which were cashed out.
    /// @param terminalToken The terminal token that the project tokens were cashed out for.
    /// @param terminalTokenAmount The amount of terminal tokens reclaimed by the cash out.
    /// @param beneficiary The beneficiary which will receive the project tokens.
    /// @param index The index of the leaf being proved in the terminal token's inbox tree.
    /// @param leaves The leaves that prove that the leaf at the `index` is in the tree (i.e. the merkle branch that the
    /// leaf is on).
    function _validateForEmergencyExit(
        uint256 projectTokenCount,
        address terminalToken,
        uint256 terminalTokenAmount,
        address beneficiary,
        uint256 index,
        bytes32[_TREE_DEPTH] calldata leaves
    )
        internal
    {
        // Make sure that the emergencyHatch is enabled for the token.
        if (!_remoteTokenFor[terminalToken].emergencyHatch && state() != JBSuckerState.DEPRECATED) {
            revert JBSucker_TokenHasInvalidEmergencyHatchState(terminalToken);
        }

        // Check that this claim is within the bounds of who can claim.
        // If the root that this leaf is in was already send then we can not let the user claim here.
        // As it could have also been received by the peer sucker, which would then let the user claim on each side.
        // NOTE: We are comparing the *count* and the *index*, so `count - 1` is the last index that was sent.
        // A count of 0 means that no root has ever been send for this token, so everyone can claim.
        JBOutboxTree storage outboxOfToken = _outboxOf[terminalToken];
        if (outboxOfToken.numberOfClaimsSent != 0 && outboxOfToken.numberOfClaimsSent - 1 >= index) {
            revert JBSucker_LeafAlreadyExecuted(terminalToken, index);
        }

        {
            // We re-use the same `_executedFor` mapping but we use a different slot.
            // We can not use the regular mapping, since this claim is done for tokens being send from here to the pair.
            // where the regular mapping is for tokens that were send on the pair to here. Even though these may seem
            // similar they are actually completely unrelated.
            address emergencyExitAddress = address(bytes20(keccak256(abi.encode(terminalToken))));

            // Make sure the leaf has not already been executed.
            if (_executedFor[emergencyExitAddress].get(index)) {
                revert JBSucker_LeafAlreadyExecuted(terminalToken, index);
            }

            // Register the leaf as executed to prevent double-spending.
            _executedFor[emergencyExitAddress].set(index);
        }

        // Calculate the root based on the leaf, the branch, and the index.
        // Compare to the current root, Revert if they do not match.
        _validateBranchRoot(
            _outboxOf[terminalToken].tree.root(), projectTokenCount, terminalTokenAmount, beneficiary, index, leaves
        );
    }

    /// @notice Validates a branch root against the expected root.
    /// @dev This is a virtual function to allow a tests to override the behavior, it should never be overwritten
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
    {
        // Calculate the root based on the leaf, the branch, and the index.
        bytes32 root = MerkleLib.branchRoot({
            _item: _buildTreeHash({
                projectTokenCount: projectTokenCount,
                terminalTokenAmount: terminalTokenAmount,
                beneficiary: beneficiary
            }),
            _branch: leaves,
            _index: index
        });

        // Compare to the current root, Revert if they do not match.
        if (root != expectedRoot) {
            revert JBSucker_InvalidProof(root, expectedRoot);
        }
    }
}
