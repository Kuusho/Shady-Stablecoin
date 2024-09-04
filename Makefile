-include .env

.PHONY: all test test-zk clean deploy fund help install snapshot format anvil install deploy deployshmood deploy-zk deployshmood-zk deploy-zk-sepolia deployshmood-zk-sepolia deploy-sepolia deploybera deployshmood-bera verify

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEFAULT_ZKSYNC_LOCAL_KEY := 0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install openzeppelin/openzeppelin-contracts --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

test-zk :; foundryup-zksync && forge test --zksync && foundryup

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

deploy:
	@forge create src/ShadyNFT.sol:ShadyNft --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --constructor-args 0x00000000000000000000000000000000000000000000d3c21bcecceda1000000 --broadcast
