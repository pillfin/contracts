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

import "./libs/BEP20.sol";
import "./libs/IChef.sol";

contract RedPillToken is BEP20('Red.Pill.Finance Token', 'RED-P') {
    uint256 constant public transferLimit = 400;
    uint256 constant public transferBase = 105;

    uint256 constant public transferFee = 100;
    uint256 constant public burnPercentage = 30;

    address constant public burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public chef;

    modifier transfer_limit(uint256 _amount, address from, address to) {
        if (!_isWhitelisted(from) && !_isWhitelisted(to)) {
            uint256 maxTransfer = circulatingSupply().mul(transferLimitRate()).div(10000);
            require(maxTransfer >= _amount, "transfer breaks transferLimit");
        }
        _;
    }

    mapping(address => bool) public accountWhitelist;

    constructor() public {}

    function setChef(address _chef) public onlyOwner {
        require (chef == address(0), "already set");
        chef = _chef;
    }

    function maxTransferAmount() public view returns (uint256) {
        uint256 maxTransfer = circulatingSupply().mul(transferLimitRate()).div(10000);
        return maxTransfer;
    }

    function _isWhitelisted(address account) internal view returns (bool) {
        bool isWhitelisted = accountWhitelist[account] == true;
        return isWhitelisted;
    }

    function addWhitelist(address account) public onlyOwner {
        accountWhitelist[account] = true;
    }

    function removeWhitelist(address account) public onlyOwner {
        accountWhitelist[account] = false;
    }

    // Anybody who wants this, please fee free to call this function.
    function burn(uint256 _amount) public {
        _burn(msg.sender, _amount);
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        require(totalSupply() == 0, "mint: already minted");
        _mint(_to, _amount);
    }
    
    function circulatingSupply() public view returns (uint256) {
        IChef _chef = IChef(chef);
        uint256 reserve = balanceOf(address(chef)).sub(_chef.lockedSupply());
        uint256 burned = balanceOf(burnAddress);
        return totalSupply()
            .sub(reserve)
            .sub(burned);
    }

    function transferLimitRate() public view returns (uint256) {
        return transferBase
            .sub(circulatingSupply()
                    .mul(100)
                    .div(totalSupply()))
            .mul(transferLimit)
            .div(100);
    }

    function chargeFee(address _sender, address _recipient, uint256 _amount) internal returns (uint256) {
        if (_isWhitelisted(_sender) || _isWhitelisted(_recipient)) {
            return 0;
        }

        uint256 fee = _amount.mul(transferFee).div(10000);
        uint256 burnAmount = fee.mul(burnPercentage).div(100);
        
        _transfer(_sender, address(chef), fee.sub(burnAmount));
        _transfer(_sender, burnAddress, burnAmount);

        return fee;
    }

    function transfer(address recipient, uint256 amount) public override transfer_limit(amount, msg.sender, recipient) returns (bool) {
        uint256 fee = chargeFee(_msgSender(), recipient, amount);
        _transfer(_msgSender(), recipient, amount.sub(fee));
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override transfer_limit(amount, sender, recipient) returns (bool) {
        uint256 fee = chargeFee(_msgSender(), recipient, amount);
        _transfer(sender, recipient, amount.sub(fee));
        _approve(
            sender,
            _msgSender(),
            allowance(sender, _msgSender()).sub(amount, 'BEP20: transfer amount exceeds allowance')
        );
        return true;
    }
}