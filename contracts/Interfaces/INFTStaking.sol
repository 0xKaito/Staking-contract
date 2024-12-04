// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface INftStaking {
    struct TokenInfo {
        address tokenOwner;
        uint256 rewardDebt;
        uint256 depositedAt;
        uint256 withdrawRequestedAt;
        uint256 withdrawAt;
        uint256 epoch;
    }

    struct NFTPoolInfo {
        bool exist;
        uint256 unbondingPeriod;
        uint256 claimRewardBuffer;
        uint256 currentEpoch;
    }

    struct EpochInfo {
        uint256 lastUpdateBlock;
        uint256 rewardPerBlock;
    }

    event LogPoolAddition(address indexed owner, address[] pool);
    event Deposit(address indexed pool, address indexed user, uint256 tokenId);
    event WithdrawRequested(address indexed pool, address indexed user, uint256 tokenId);
    event Withdraw(address indexed pool, address indexed user, uint256 tokenId);
    event Claimed(address indexed pool, address indexed user, address indexed receiver, uint256 rewardAmount);
    event RewardPerBlockUpdated(address pool, uint256 rewardAmountPerBlock);

    error UnmatchedPoolLength();
    error ZeroPoolAddress();
    error UserAlreadyExists();
    error PoolDoesNotExist();
    error WithdrawalAlreadyRequested();
    error WithdrawalNotRequested();
    error UnbondingPeriodNotElapsed();
    error NFTNotWithdrawnYet();
    error ClaimBufferNotElapsed();
    error ZeroRewardToWithdraw();
    error InvalidRewardAmount();
    error InvalidTokenOwner();

    function initialize(address _admin, address _REWARDTOKEN) external;
    function addPool(
        address[] memory _pool,
        uint256[] memory _rewardPerBlock,
        uint256[] memory _unBondingPeriod,
        uint256[] memory _claimRewardBuffer
    ) external;
    function updateRewardPerBlock(address _poolAddress, uint256 _rewardAmountPerBlock) external;
    function deposit(address _pool, uint256 _tokenId) external;
    function requestWithdraw(address _pool, uint256 _tokenId) external;
    function withdraw(address _pool, uint256 _tokenId) external;
    function claimRewards(address _pool, uint256 _tokenId, address _to) external;
    function pause() external;
    function unpause() external;

    function batchUpdateRewardPerBlock(address[] calldata _poolAddresses, uint256[] calldata _rewardAmountsPerBlock)
        external;
}