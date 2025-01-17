import "@nomiclabs/hardhat-waffle"
import "@typechain/hardhat"
import "hardhat-abi-exporter"
import 'hardhat-dependency-compiler'
import "hardhat-gas-reporter"
import "solidity-coverage"
import "tsconfig-paths/register"

const hardhatConfig = {
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true,
            initialBaseFeePerGas: 0, // remove when the following issue is fixed: https://github.com/sc-forks/solidity-coverage/issues/652
        },
        localhost: { url: "http://localhost:7545" },
        fork: {
            url: "http://localhost:7545",
        },
        // export the NODE_URL environment variable to use remote nodes like Alchemy or Infura. eg
        // export NODE_URL=https://eth-mainnet.alchemyapi.io/v2/yourApiKey
        env: { url: process.env.NODE_URL || "" },
        ropsten: {
            url: process.env.NODE_URL || "",
            gasPrice: 30000000000,
            gasLimit: 8000000,
        },
        mainnet: {
            url: process.env.NODE_URL || "",
        },
    },
    abiExporter: {
        path: "./abis",
        clear: true,
        flat: true,
        only: ["MStableYieldSource"],
    },
    paths: { artifacts: "./build" },
    dependencyCompiler: {
        paths: [
            '@mstable/protocol/contracts/masset/Masset.sol',
        ],
    },
    gasReporter: {
        currency: "USD",
        gasPrice: 30,
    },
    mocha: {
        timeout: 30000,
    },
    solidity: {
        version: "0.8.6",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    typechain: {
        outDir: "types/pooltogether",
        target: "ethers-v5",
    },
}

export default hardhatConfig
