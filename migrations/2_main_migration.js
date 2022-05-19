const TwToken = artifacts.require("TwToken");
const TwtStakingPool = artifacts.require("TwtStakingPool");

module.exports = async function (deployer, _, [owner]) {
  console.log('Deploying');
  
  await deployer.deploy(TwToken);
  await deployer.deploy(TwtStakingPool, "0");

  const pool = await TwtStakingPool.deployed();

  console.log('Deployed, pool setup starting...');
 
  await pool.addPool(TwToken.address, "250", "1000000000000000000000", "100000000000", "15552000", "5000");
  console.log('Pool setup finished.');
};
