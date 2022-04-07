// @ts-ignore
import { ethers, upgrades } from 'hardhat';
import { contractAddresses } from '../constants/index';
require('dotenv').config();

async function deployLibrary() {
  const libraryContract = await ethers.getContractFactory('IterableMapping');
  const libraryInstance = await libraryContract.deploy([]);
  console.log('Library contract deployed: %s', libraryInstance.address);
}

async function deployToken() {
  // await deployLibrary();

  if (!contractAddresses[process.env.NETWORK]?.token) {
    const tokenContract = await ethers.getContractFactory('HotDoge', {
      libraries: {
        IterableMapping: '0xEa724984F07f84146e0363c559EBEBE135426960',
      },
    });
    const tokenInstance = await tokenContract.deploy([]);
    console.log('Token contract deployed: %s', tokenInstance.address);
  }
}

async function deployStaking() {
  if (!contractAddresses[process.env.NETWORK]?.staking) {
    const stakingContract = await ethers.getContractFactory('HotDogeStaking');
    const stakingInstance = await upgrades.deployProxy(stakingContract, []);
    console.log('Staking contract deployed: %s', stakingInstance.address);
  }
}

async function main() {
  // await deployToken();
  await deployStaking();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
