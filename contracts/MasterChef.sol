//     _______  __ __ __    ________ __                                                             
//    |       \|  \  \  \  |        \  \                                                            
//    | ▓▓▓▓▓▓▓\\▓▓ ▓▓ ▓▓  | ▓▓▓▓▓▓▓▓\▓▓_______   ______  _______   _______  ______                 
//    | ▓▓__/ ▓▓  \ ▓▓ ▓▓  | ▓▓__   |  \       \ |      \|       \ /       \/      \                
//    | ▓▓    ▓▓ ▓▓ ▓▓ ▓▓  | ▓▓  \  | ▓▓ ▓▓▓▓▓▓▓\ \▓▓▓▓▓▓\ ▓▓▓▓▓▓▓\  ▓▓▓▓▓▓▓  ▓▓▓▓▓▓\               
//    | ▓▓▓▓▓▓▓| ▓▓ ▓▓ ▓▓  | ▓▓▓▓▓  | ▓▓ ▓▓  | ▓▓/      ▓▓ ▓▓  | ▓▓ ▓▓     | ▓▓    ▓▓               
//    | ▓▓     | ▓▓ ▓▓ ▓▓__| ▓▓     | ▓▓ ▓▓  | ▓▓  ▓▓▓▓▓▓▓ ▓▓  | ▓▓ ▓▓_____| ▓▓▓▓▓▓▓▓               
//    | ▓▓     | ▓▓ ▓▓ ▓▓  \ ▓▓     | ▓▓ ▓▓  | ▓▓\▓▓    ▓▓ ▓▓  | ▓▓\▓▓     \\▓▓     \               
//     \▓▓      \▓▓\▓▓\▓▓\▓▓\▓▓      \▓▓\▓▓   \▓▓ \▓▓▓▓▓▓▓\▓▓   \▓▓ \▓▓▓▓▓▓▓ \▓▓▓▓▓▓▓               
//
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';

import "./RedPillToken.sol";
import "./libs/IChef.sol";

// This contract is a fork of the MasterChef contract of Pancakewap with
// multiple additions and changes.
// Feel free to read it all!
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of CAKEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCakePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCakePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. CAKEs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that CAKEs distribution occurs.
        uint256 accCakePerShare; // Accumulated CAKEs per share, times 1e12. See below.
    }

    struct PoolProps {
        uint256 tokenTotal;
        uint256 depositFee;
        IBEP20 delRewardToken;
        IChef delChef;
        uint256 delPid;
    }

    // The CAKE TOKEN!
    RedPillToken public cake;
    // Dev address.
    address public devaddr;
    uint256 public devReward = 10;
    // CAKE tokens created per block.
    uint256 public cakePerBlock;
    // Bonus muliplier for early cake makers.
    uint256 public BONUS_MULTIPLIER = 1;

    address public feeAddr;
    
    // Info of each pool.
    PoolInfo[] public poolInfo;
    PoolProps[] public poolProps;

    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when CAKE mining starts.
    uint256 public startBlock;
    uint256 public lastDelegate = 0;

    uint256 public rewardPeriod = 1200; // Blocks
    uint256 private lastRewardUpdate = 0; // Invisible to make timing the market harder
    uint256 public rewardReserve = 30*24*1200;

    bool public active = false;

    modifier rebalance() {
        rebalanceBlockReward();
        _;
    }

    modifier validatePool(uint256 _pid) {
        require(_pid < poolInfo.length, "validatePool: pool exists?");
        _;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event BlockReward(uint256 reward);

    constructor(
        RedPillToken _cake,
        address _devaddr,
        uint256 _cakePerBlock,
        uint256 _startBlock
    ) public {
        cake = _cake;
        devaddr = _devaddr;
        cakePerBlock = _cakePerBlock;
        startBlock = _startBlock;
        feeAddr = msg.sender;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _cake,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accCakePerShare: 0
        }));

        poolProps.push(PoolProps({
            depositFee: 0,
            tokenTotal: 0,
            delRewardToken: IBEP20(0),
            delChef: IChef(0),
            delPid: 0
        }));

        totalAllocPoint = 1000;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function checkPoolDuplicate(IBEP20 _lpToken) public view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: existing pool");
        }
    }

    function activate(uint256 _startBlock) public onlyOwner {
        require(!active, 'activate: already active');
        require(_startBlock > block.number, 'no retroactivity');
        startBlock = _startBlock;
        active = true;

        for (uint256 _pid = 0; _pid < poolInfo.length; _pid++) {
            poolInfo[_pid].lastRewardBlock = _startBlock;
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner rebalance {
        checkPoolDuplicate(_lpToken);
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accCakePerShare: 0
        }));
        poolProps.push(PoolProps({
            depositFee: 0,
            tokenTotal: 0,
            delRewardToken: IBEP20(0),
            delChef: IChef(0),
            delPid: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's CAKE allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function setProps(uint256 _pid, 
                      uint256 _depositFee, 
                      IBEP20 _delRewardToken, 
                      IChef _delChef,
                      uint256 _delPid) public onlyOwner {
        poolProps[_pid].depositFee = _depositFee;

        if (poolProps[_pid].tokenTotal == 0) {
            poolProps[_pid].delRewardToken = _delRewardToken;
            poolProps[_pid].delChef = _delChef;
            poolProps[_pid].delPid = _delPid;
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(4);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points.div(100).mul(100);
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending CAKEs on frontend.
    function pendingCake(uint256 _pid, address _user) external view returns (uint256) {
        if (!active) {
            return 0;
        }
        
        PoolInfo storage pool = poolInfo[_pid];
        PoolProps storage _poolProps = poolProps[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accCakePerShare = pool.accCakePerShare;
        uint256 lpSupply = _poolProps.tokenTotal;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 cakeReward = multiplier.mul(cakePerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accCakePerShare = accCakePerShare.add(cakeReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accCakePerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public rebalance {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePool(_pid) rebalance {
        if (!active) {
            return;
        }

        PoolInfo storage pool = poolInfo[_pid];
        PoolProps storage _poolProps = poolProps[_pid];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = _poolProps.tokenTotal;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 cakeReward = multiplier.mul(cakePerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        safeCakeTransfer(devaddr, cakeReward.div(devReward));
        
        pool.accCakePerShare = pool.accCakePerShare.add(cakeReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for CAKE allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) public rebalance validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        PoolProps storage _poolProps = poolProps[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        setReferrer(_referrer);
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCakePerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeCakeTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 depositFee = chargeDepositFee(_pid, _amount);
            user.amount = user.amount.add(_amount.sub(depositFee));
            _poolProps.tokenTotal = _poolProps.tokenTotal.add(_amount.sub(depositFee));
            delegateDeposit(_pid, _amount.sub(depositFee));
        }
        user.rewardDebt = user.amount.mul(pool.accCakePerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function chargeDepositFee(uint256 _pid, uint256 _amount) internal returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        PoolProps storage _poolProps = poolProps[_pid];
        
        if (_poolProps.depositFee > 0) {
            uint256 depositFee = _amount
                .mul(_poolProps.depositFee)
                .div(10000);

            uint256 referralReward;
            uint256 referralReward2;
            address referrer = address(getReferrer(msg.sender));
            if (referrer != address(0) && referrer != msg.sender) {
                referralReward = depositFee.mul(referralShare).div(10000);
                rewardReferral(_pid, referralReward, referrer);

                address referrer2 = address(getReferrer(referrer));    
                if (referrer2 != address(0) && referrer2 != msg.sender) {
                    referralReward2 = referralReward.mul(referralShare).div(10000);
                    rewardReferral(_pid, referralReward2, referrer2);
                    referralReward = referralReward.add(referralReward2);
                }
            }

            uint256 devShare = depositFee.mul(devReward).div(100);
            
            pool.lpToken.safeTransfer(address(devaddr), devShare);
            pool.lpToken.safeTransfer(address(feeAddr), depositFee.sub(referralReward).sub(devShare));

            return depositFee;
        }

        return 0;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public rebalance validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        PoolProps storage _poolProps = poolProps[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        delegateWithdraw(_pid, _amount);
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accCakePerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeCakeTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            _poolProps.tokenTotal = _poolProps.tokenTotal.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCakePerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function delegateDeposit(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        PoolProps storage _poolProps = poolProps[_pid];
        
        if (_poolProps.delPid > 0) {
            if (pool.lpToken.allowance(address(this), address(_poolProps.delChef)) < 10**26) {
                pool.lpToken.approve(address(_poolProps.delChef), 10**26);
            }
            
            _poolProps.delChef.deposit(_poolProps.delPid, _amount);
        }
    }

    function delegateWithdraw(uint256 _pid, uint256 _amount) internal {
        PoolProps storage _poolProps = poolProps[_pid];
       
        if (_poolProps.delPid > 0) {
            IChef delegate = _poolProps.delChef;
            IBEP20 delegateReward = _poolProps.delRewardToken;
            delegate.withdraw(_poolProps.delPid, _amount);            
            
            if (lastDelegate.add(1200) < block.number || lastDelegate == 0) {
                uint256 reward = delegateReward.balanceOf(address(this));
                uint256 devRwd = reward.mul(devReward).div(100);
                delegateReward.safeTransfer(devaddr, devRwd);
                delegateReward.safeTransfer(feeAddr, reward.sub(devRwd));
                lastDelegate = block.number;
            }
        }
    }

    function delegateHarvestAll() public {
        for (uint256 pid; pid < poolInfo.length; pid++) {
            if (address(poolProps[pid].delChef) != address(0)) {
                delegateWithdraw(poolProps[pid].delPid, 0);
            }
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        PoolProps storage _poolProps = poolProps[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        delegateWithdraw(_poolProps.delPid, user.amount);
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        _poolProps.tokenTotal = _poolProps.tokenTotal.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe cake transfer function, just in case if rounding error causes pool to not have enough CAKEs.
    function safeCakeTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBal = cake.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > rewardBal) {
            transferSuccess = cake.transfer(_to, rewardBal);
        } else {
            transferSuccess = cake.transfer(_to, _amount);
        }
        require(transferSuccess, "safeCakeTransfer: transfer failed");
    }

    // Function to remove liquidity from delegation in delegated pool in case a pool gets inactive
    // an addDelegation function could be added, but this will also introduce the risk
    // of abuse using a secondary contract that implements IChef and can be used to
    // clear the contract of all funds. As this is a potential risk the absense of
    // an addDelegation function is the payoff for security.
    function removeDelegation(uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        PoolProps storage _poolProps = poolProps[_pid];
        
        uint balance = pool.lpToken.balanceOf(address(this));
        delegateWithdraw(_poolProps.delPid, balance);

        _poolProps.delRewardToken = IBEP20(0);
        _poolProps.delChef = IChef(0);
        _poolProps.delPid = 0;
    }

    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function fee(address _feeAddr) public {
        require(msg.sender == feeAddr, "fee: wut?");
        feeAddr = _feeAddr;
    }

    event Rebalance(uint256 _old, uint256 _new);

    function rebalanceBlockReward() internal {
        if (lastRewardUpdate.add(rewardPeriod) > block.number && lastRewardUpdate != 0) {
            return;
        }
        
        uint256 oldReward = cakePerBlock;
        uint256 reserve = cake.balanceOf(address(this)).sub(_lockedSupply());
        cakePerBlock = reserve.div(rewardReserve);
        lastRewardUpdate = block.number;

        emit Rebalance(oldReward, cakePerBlock);
    }

    function _lockedSupply() internal view returns(uint256) {
        uint256 locked;
        
        for (uint256 pid; pid < poolInfo.length; pid++) {
            if (address(cake) == address(poolInfo[pid].lpToken)) {
                locked = locked.add(poolProps[pid].tokenTotal);
            }
        }
        return locked;
    }

    function lockedSupply() external view returns(uint256) {
        return _lockedSupply();
    }


    struct ReferralReward {
        uint256 rewardBlock;
        uint256 pid;
        uint256 amount;
    }

    struct ReferrerAddress {
        address referrer;
    }

    uint256 public referralShare = 1000;
    mapping (address => mapping (address => ReferralReward[])) public referrals;
    mapping (address => ReferrerAddress) public referrers;
    
    event Referral(address indexed referral, address indexed referrer, uint256 indexed pid, uint256 amount);

    function setReferralShare(uint256 _share) public {
        require(_share >= 0 && _share <= 10000, "out of range");
        referralShare = _share;
    }

    function setReferrer(address _referrer) internal {
        // Cannot change referrer
        if (getReferrer(msg.sender) != address(0)) {
            return;
        }

        // No referrer no attribution
        if (_referrer == address(0)) {
            return;
        }

        // Do not refer yourself
        if (_referrer == address(msg.sender)) {
            return;
        }

        ReferrerAddress storage referrerAddress = referrers[msg.sender];
        referrerAddress.referrer = _referrer;
    }

    function getReferrer(address sender) internal view returns (address referrer) {
        ReferrerAddress storage referrerAddress = referrers[sender];
        referrer = address(referrerAddress.referrer);
    }

    function rewardReferral(uint256 _pid, uint256 _amount, address _referrer) internal {
        // Cannot refer yourself
        if (_referrer == address(msg.sender)) {
            return;
        }

        // Nothing to transfer
        if (_amount <= 0) {
            return;
        }

        PoolInfo storage pool = poolInfo[_pid];
        
        pool.lpToken.safeTransfer(_referrer, _amount);
        referrals[_referrer][address(msg.sender)].push(ReferralReward({
            rewardBlock: block.number,
            pid: _pid,
            amount: _amount
        }));

        emit Referral(msg.sender, _referrer, _pid, _amount);
    }
}
