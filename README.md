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
