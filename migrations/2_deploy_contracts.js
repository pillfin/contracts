const Token = artifacts.require("RedPillToken");
const MasterChef = artifacts.require("MasterChef");

const DEV_ADDRESS = '0xC9139f4ccBB519a8e5940749Bbd782530811239C';
const FEE_ADDRESS = '0xeD29936d67D9885Bc08DA206FADccA55Eb3637cF';
const DEPLOY_ADDRESS = '0xf50398655a5427c84eA8c998a31BeE118C359449';
const ROUTER = '0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F'

const TOTAL_SUPPLY = '100000000000000000000000';
const INITIAL_RESERVE = '75000000000000000000000';

module.exports = async function(deployer) {
    await deployer.deploy(Token);
    const token = await Token.deployed();

    await deployer.deploy(MasterChef, Token.address, DEV_ADDRESS, 1, 0);
    const chef = await MasterChef.deployed();
    
    // Set Chef on Token
    await token.setChef(MasterChef.address);

    // Set Fee Address
    await chef.fee(FEE_ADDRESS);

    // Whitelisting
    await token.addWhitelist(MasterChef.address);
    await token.addWhitelist(DEPLOY_ADDRESS);
    await token.addWhitelist(DEV_ADDRESS);
    await token.addWhitelist(ROUTER);

    // Mint to Deploy address
    await token.mint(DEPLOY_ADDRESS, TOTAL_SUPPLY);
    await token.transfer(MasterChef.address, INITIAL_RESERVE);

    // Rebalance
    await chef.updatePool(0);

    // Activate
    await chef.activate('5732580')
};
