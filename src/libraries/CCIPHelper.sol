// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @notice Global constants used across Juicebox contracts.
library CCIPHelper {
    /// @notice The respective CCIP router used by the chain
    address public constant ETH_ROUTER = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    address public constant ETH_SEP_ROUTER = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
    address public constant OP_ROUTER = 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f;
    address public constant ARB_ROUTER = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
    address public constant ARB_SEP_ROUTER = 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165;
    address public constant POLY_ROUTER = 0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe;
    address public constant AVA_ROUTER = 0xF4c7E640EdA248ef95972845a62bdC74237805dB;
    address public constant BNB_ROUTER = 0x34B03Cb9086d7D758AC55af71584F81A598759FE;
    address public constant BASE_ROUTER = 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;

    /// @notice The respective chain ids per network
    uint256 public constant ETH_ID = 1;
    uint256 public constant ETH_SEP_ID = 11155111;
    uint256 public constant OP_ID = 10;
    uint256 public constant ARB_ID = 42161;
    uint256 public constant ARB_SEP_ID = 421614;
    uint256 public constant POLY_ID = 137;
    uint256 public constant AVA_ID = 43114;
    uint256 public constant BNB_ID = 56;
    uint256 public constant BASE_ID = 8453;

    /// @notice The chain selector per network
    uint64 public constant ETH_SEL = 5009297550715157269;
    uint64 public constant ETH_SEP_SEL = 16015286601757825753;
    uint64 public constant OP_SEL = 3734403246176062136;
    uint64 public constant ARB_SEL = 4949039107694359620;
    uint64 public constant ARB_SEP_SEL = 3478487238524512106;
    uint64 public constant POLY_SEL = 4051577828743386545;
    uint64 public constant AVA_SEL = 6433500567565415381;
    uint64 public constant BNB_SEL = 11344663589394136015;
    uint64 public constant BASE_SEL = 15971525489660198786;

    /// @notice The WETH address of each chain
    address public constant ETH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ETH_SEP_WETH = 0x097D90c9d3E0B50Ca60e1ae45F6A81010f9FB534;
    address public constant OP_WETH = 0x4200000000000000000000000000000000000006;
    address public constant ARB_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant ARB_SEP_WETH = 0xE591bf0A0CF924A0674d7792db046B23CEbF5f34;
    address public constant POLY_WETH = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant AVA_WETH = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public constant BNB_WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant BASE_WETH = 0x4200000000000000000000000000000000000006;

    function routerOfChain(uint256 _chainId) public pure returns (address router) {
        if (_chainId == ETH_ID) {
            return ETH_ROUTER;
        } else if (_chainId == OP_ID) {
            return OP_ROUTER;
        } else if (_chainId == ARB_ID) {
            return ARB_ROUTER;
        } else if (_chainId == POLY_ID) {
            return POLY_ROUTER;
        } else if (_chainId == AVA_ID) {
            return AVA_ROUTER;
        } else if (_chainId == BNB_ID) {
            return BNB_ROUTER;
        } else if (_chainId == BASE_ID) {
            return BASE_ROUTER;
        } else if (_chainId == ETH_SEP_ID) {
            return ETH_SEP_ROUTER;
        } else if (_chainId == ARB_SEP_ID) {
            return ARB_SEP_ROUTER;
        } else {
            revert("Unsupported chain");
        }
    }

    function selectorOfChain(uint256 _chainId) public pure returns (uint64 selectorId) {
        if (_chainId == ETH_ID) {
            return ETH_SEL;
        } else if (_chainId == OP_ID) {
            return OP_SEL;
        } else if (_chainId == ARB_ID) {
            return ARB_SEL;
        } else if (_chainId == POLY_ID) {
            return POLY_SEL;
        } else if (_chainId == AVA_ID) {
            return AVA_SEL;
        } else if (_chainId == BNB_ID) {
            return BNB_SEL;
        } else if (_chainId == BASE_ID) {
            return BASE_SEL;
        } else if (_chainId == ETH_SEP_ID) {
            return ETH_SEP_SEL;
        } else if (_chainId == ARB_SEP_ID) {
            return ARB_SEP_SEL;
        } else {
            revert("Unsupported chain");
        }
    }

    function wethOfChain(uint256 _chainId) public pure returns (address weth) {
        if (_chainId == ETH_ID) {
            return ETH_WETH;
        } else if (_chainId == OP_ID) {
            return OP_WETH;
        } else if (_chainId == ARB_ID) {
            return ARB_WETH;
        } else if (_chainId == POLY_ID) {
            return POLY_WETH;
        } else if (_chainId == AVA_ID) {
            return AVA_WETH;
        } else if (_chainId == BNB_ID) {
            return BNB_WETH;
        } else if (_chainId == BASE_ID) {
            return BASE_WETH;
        } else if (_chainId == ETH_SEP_ID) {
            return ETH_SEP_WETH;
        } else if (_chainId == ARB_SEP_ID) {
            return ARB_SEP_WETH;
        } else {
            revert("Unsupported chain");
        }
    }
}
