// @ts-ignore
import { ethers, upgrades } from 'hardhat';
import { contractAddresses } from '../constants/index';
require('dotenv').config();

async function upgradeStaking() {
  const proxyAddress = contractAddresses[process.env.NETWORK]?.staking;
  if (proxyAddress) {
    const stakingContract = await ethers.getContractFactory('HotDogeStaking');
    const stakingInstance = await upgrades.upgradeProxy(
      proxyAddress,
      stakingContract
    );
    console.log('Staking contract upgraded: %s', stakingInstance.address);
  }
}

async function main() {
  await upgradeStaking();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
