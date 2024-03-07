// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Staking {

    struct UserInfo {
        uint256 amount;
        uint256 pendingReward;
        uint256 lastUpdateBN;
    }

    IERC20 public immutable REWARD_TOKEN;

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor(address _defiToken) {
        REWARD_TOKEN = IERC20(_defiToken);
    }

    function getPendingReward(address _user) external view returns(uint256 pendingAmount_) {
        UserInfo memory _userInfo = userInfo[_user];

        if (_userInfo.lastUpdateBN == block.number) return _userInfo.pendingReward;

        pendingAmount_ = _userInfo.pendingReward + _calculatePending(_userInfo.amount, _userInfo.lastUpdateBN);
    }

    function deposit(uint256 _amount) external {
        
        UserInfo memory _userInfo = userInfo[msg.sender];
        _userInfo.pendingReward += _calculatePending(_userInfo.amount, _userInfo.lastUpdateBN);
        _userInfo.amount += _amount;
        _userInfo.lastUpdateBN = block.number;

        userInfo[msg.sender] = _userInfo;
    
        REWARD_TOKEN.transferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw() external {  

        UserInfo memory _userInfo = userInfo[msg.sender];

        uint256 _totalAmount = _userInfo.pendingReward + _calculatePending(_userInfo.amount, _userInfo.lastUpdateBN) + _userInfo.amount;

        delete userInfo[msg.sender];

        REWARD_TOKEN.transfer(msg.sender, _totalAmount);

        emit Withdraw(msg.sender, _totalAmount);
    }

    function _calculatePending(uint256 _amount, uint256 _lastUpdateNumber) internal view returns(uint256) {
        return ((block.number - _lastUpdateNumber) * _amount);
    }
    
}
