// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./Interfaces/INFTStaking.sol";

contract NftStaking is
    INftStaking,
    UUPSUpgradeable,
    IERC721Receiver,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    IERC20 public REWARDTOKEN;

    mapping(address => NFTPoolInfo) public poolInfo;
    mapping(address => mapping(uint256 => TokenInfo)) public tokenInfo;
    mapping(address => mapping(uint256 => EpochInfo)) public epochInfo;

    function initialize(address _admin, address _REWARDTOKEN) public override initializer {
        __Ownable_init(_admin);
        __ReentrancyGuard_init();
        __Pausable_init();
        REWARDTOKEN = IERC20(_REWARDTOKEN);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function addPool(
        address[] memory _pool,
        uint256[] memory _rewardPerBlock,
        uint256[] memory _unBondingPeriod,
        uint256[] memory _claimRewardBuffer
    ) external override onlyOwner {
        if (
            _pool.length != _rewardPerBlock.length || _rewardPerBlock.length != _unBondingPeriod.length
                || _unBondingPeriod.length != _claimRewardBuffer.length
        ) {
            revert UnmatchedPoolLength();
        }

        for (uint256 i; i < _pool.length; ++i) {
            if (_pool[i] == address(0)) revert ZeroPoolAddress();
            poolInfo[_pool[i]].exist = true;
            poolInfo[_pool[i]].currentEpoch = 0;
            poolInfo[_pool[i]].unbondingPeriod = _unBondingPeriod[i];
            poolInfo[_pool[i]].claimRewardBuffer = _claimRewardBuffer[i];
            epochInfo[_pool[i]][0].rewardPerBlock = _rewardPerBlock[i];
            epochInfo[_pool[i]][0].lastUpdateBlock = block.number;
        }

        emit LogPoolAddition(msg.sender, _pool);
    }

    function updateRewardPerBlock(address _poolAddress, uint256 _rewardAmountPerBlock) external onlyOwner {
        if (_poolAddress == address(0)) revert ZeroPoolAddress();
        if (!poolInfo[_poolAddress].exist) revert PoolDoesNotExist();
        uint256 _epoch = poolInfo[_poolAddress].currentEpoch++;
        epochInfo[_poolAddress][_epoch].rewardPerBlock = _rewardAmountPerBlock;
        epochInfo[_poolAddress][_epoch].lastUpdateBlock = block.number;
        emit RewardPerBlockUpdated(_poolAddress, _rewardAmountPerBlock);
    }

    function batchUpdateRewardPerBlock(address[] calldata _poolAddresses, uint256[] calldata _rewardAmountsPerBlock)
        external
        onlyOwner
    {
        if (_poolAddresses.length != _rewardAmountsPerBlock.length) {
            revert UnmatchedPoolLength();
        }

        for (uint256 i = 0; i < _poolAddresses.length; i++) {
            address _poolAddress = _poolAddresses[i];
            uint256 _rewardAmountPerBlock = _rewardAmountsPerBlock[i];

            if (_poolAddress == address(0)) revert ZeroPoolAddress();
            if (!poolInfo[_poolAddress].exist) revert PoolDoesNotExist();

            uint256 _epoch = poolInfo[_poolAddress].currentEpoch++;
            epochInfo[_poolAddress][_epoch].rewardPerBlock = _rewardAmountPerBlock;
            epochInfo[_poolAddress][_epoch].lastUpdateBlock = block.number;

            emit RewardPerBlockUpdated(_poolAddress, _rewardAmountPerBlock);
        }
    }

    function deposit(address _pool, uint256 _tokenId) external whenNotPaused {
        if (!poolInfo[_pool].exist) revert PoolDoesNotExist();
        address depositor = msg.sender;
        TokenInfo memory _tokenInfo = tokenInfo[_pool][_tokenId];
        if (_tokenInfo.tokenOwner != address(0)) revert UserAlreadyExists();

        _tokenInfo.tokenOwner = depositor;
        _tokenInfo.depositedAt = block.number;
        _tokenInfo.epoch = poolInfo[_pool].currentEpoch;
        tokenInfo[_pool][_tokenId] = _tokenInfo;

        IERC721(_pool).safeTransferFrom(depositor, address(this), _tokenId);

        emit Deposit(_pool, depositor, _tokenId);
    }

    function requestWithdraw(address _pool, uint256 _tokenId) external nonReentrant {
        if (!poolInfo[_pool].exist) revert PoolDoesNotExist();
        address withdrawer = msg.sender;

        TokenInfo memory _tokenInfo = tokenInfo[_pool][_tokenId];
        if (_tokenInfo.tokenOwner != withdrawer) revert InvalidTokenOwner();
        if (_tokenInfo.withdrawRequestedAt != 0) revert WithdrawalAlreadyRequested();

        _tokenInfo.withdrawRequestedAt = block.number;
        tokenInfo[_pool][_tokenId] = _tokenInfo;

        emit WithdrawRequested(_pool, withdrawer, _tokenId);
    }

    function withdraw(address _pool, uint256 _tokenId) external nonReentrant {
        if (!poolInfo[_pool].exist) revert PoolDoesNotExist();

        address withdrawer = msg.sender;
        TokenInfo memory _tokenInfo = tokenInfo[_pool][_tokenId];
        if (_tokenInfo.tokenOwner != withdrawer) revert InvalidTokenOwner();
        if (_tokenInfo.withdrawRequestedAt == 0) revert WithdrawalNotRequested();
        if (block.number < (_tokenInfo.withdrawRequestedAt + poolInfo[_pool].unbondingPeriod)) {
            revert UnbondingPeriodNotElapsed();
        }

        _tokenInfo.withdrawRequestedAt = 0;
        _tokenInfo.withdrawAt = block.number;
        tokenInfo[_pool][_tokenId] = _tokenInfo;

        IERC721(_pool).transferFrom(address(this), msg.sender, _tokenId);

        emit Withdraw(_pool, withdrawer, _tokenId);
    }

    function claimRewards(address _pool, uint256 _tokenId, address _to) external nonReentrant {
        if (!poolInfo[_pool].exist) revert PoolDoesNotExist();

        address rewardClaimer = msg.sender;
        TokenInfo memory _tokenInfo = tokenInfo[_pool][_tokenId];
        if (_tokenInfo.tokenOwner != rewardClaimer) revert InvalidTokenOwner();
        if (!isRewardWithdrawable(_pool, _tokenId)) {
            revert ClaimBufferNotElapsed();
        }

        uint256 reward = _calculateRewardAccumulated(_tokenInfo.depositedAt, _tokenInfo.epoch, poolInfo[_pool].currentEpoch, _pool);
        if (reward == 0) revert ZeroRewardToWithdraw();

        _tokenInfo.rewardDebt = 0;
        _tokenInfo.epoch = 0;
        _tokenInfo.depositedAt = 0;
        _tokenInfo.withdrawAt = 0;
        _tokenInfo.tokenOwner = address(0);
        tokenInfo[_pool][_tokenId] = _tokenInfo;

        REWARDTOKEN.safeTransfer(_to, reward);

        emit Claimed(_pool, rewardClaimer, _to, reward);
    }

    function isRewardWithdrawable(address _pool, uint256 _tokenId) public view returns (bool isWithdrawable) {
        TokenInfo memory _tokenInfoData = tokenInfo[_pool][_tokenId];
        if (_tokenInfoData.withdrawAt == 0) revert NFTNotWithdrawnYet();

        if (block.number < _tokenInfoData.withdrawAt + poolInfo[_pool].claimRewardBuffer) {
            isWithdrawable = false;
        } else {
            isWithdrawable = true;
        }
    }

    function getAccumulatedReward(address _pool, uint256 _tokenId) external view returns (uint256 accumulatedReward) {
        TokenInfo memory _tokenInfoData = tokenInfo[_pool][_tokenId];
        if (_tokenInfoData.depositedAt == 0) {
            return 0;
        }
        accumulatedReward = _calculateRewardAccumulated(_tokenInfoData.depositedAt, _tokenInfoData.epoch, poolInfo[_pool].currentEpoch, _pool);
    }

    function _calculateRewardAccumulated(uint256 _depositedAt, uint256 _epoch, uint256 _currentEpoch, address _pool)
        internal
        view
        returns (uint256 accumulatedRewards)
    {
        for (uint256 i = _epoch; i <= _currentEpoch; ++i) {
            uint256 _rewardPerBlock = epochInfo[_pool][i].rewardPerBlock;
            uint256 _nextLastUpdateBlock = i == _currentEpoch ? block.number : epochInfo[_pool][i+1].lastUpdateBlock;
            uint256 _LastUpdateBlock = i == _epoch ? _depositedAt : epochInfo[_pool][i].lastUpdateBlock;
            accumulatedRewards += (_nextLastUpdateBlock -_LastUpdateBlock) * _rewardPerBlock;
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}