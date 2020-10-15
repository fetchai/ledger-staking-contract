const Migrations = artifacts.require("Migrations");

module.exports = function(deployer, network) {
    if (!network.includes("development")) {
        return;
    }

    deployer.deploy(Migrations);
};
