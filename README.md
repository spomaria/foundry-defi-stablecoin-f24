# Project Overview

# Setting out
Create a new repository using the below command
```bash
mkdir foundry-defi-stablecoin-f24
cd foundry-defi-stablecoin-f24
```

Initialize the repository as a foundry project using the below command
```bash
forge init
```

Download dependencies from `openzeppelin` using the below command
```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```

Add a `remappings` section in the `foundry.toml` in the following manner
```
remappings = ["@openzeppelin=lib/openzeppelin-contracts"]
```

Since we shall make use of price feed from Chainlink to determine the value of collateral in USD, we shall download dependencies using the following command
```bash
forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit
```

Next, we go to our `foundry.toml` file and use remappings to redirect our imports to the location of the relevant file imports on our local machine. This is because sometimes, when we download dependencies on our local machine, the file path may vary from what the github repo is. We remap in `foundry.toml` using the following command
```
remappings = ["@openzeppelin=lib/openzeppelin-contracts",
"@chainlink/contracts/src/v0.8/shared/interfaces/ = /lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/"]
```