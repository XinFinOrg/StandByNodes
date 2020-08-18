const solc = require("solc");
const path = require("path");
const fs = require("fs");

let { InstanceEmitter } = require("./connection");

let heartbeatRef = null,
  xdc;

function HeartBeat() {
  clearInterval(heartbeatRef);
  heartbeatRef = setInterval(async () => {
    try {
      console.log(`${__filename}::LISTENING`, await xdc.eth.net.isListening());
    } catch (e) {
      console.trace(e);
    }
  }, 5000);
}

InstanceEmitter.on("xdc", () => {
  console.log(`[*] updating XDC on event @@@@@@@@@@@@@@@@`);
  xdc = require("./connection").xdc;
  HeartBeat();
});

function findImports(path) {
  if (path === "Ownable.sol")
    return {
      contents: getContractSource("Ownable"),
    };
  else return { error: "File not found" };
}

function getContractSource(name) {
  return fs.readFileSync(
    path.join(__dirname, `../../contracts/${name}.sol`),
    "UTF-8"
  );
}

function DeployStakingContract() {
  return new Promise((resolve, reject) => {
    const source = fs.readFileSync(
      path.join(__dirname, "../../contracts/StakingContract.sol"),
      "UTF-8"
    );
    const input = {
      language: "Solidity",
      sources: {
        "StakingContract.sol": {
          content: source,
        },
      },
      settings: {
        outputSelection: {
          "*": {
            "*": ["*"],
          },
        },
      },
    };

    const compiledCode = JSON.parse(
      solc.compile(JSON.stringify(input), { import: findImports })
    );
    const StakingReqards =
      compiledCode.contracts["StakingContract.sol"]["StakingRewards"];

    let data =
      "0x" +
      StakingReqards.evm.bytecode.object +
      xdc.eth.abi
        .encodeParameters(
          ["uint256", "uint256", "uint256", "address", "uint256"],
          ["1", "1", "1", process.env.validatorAddress, "31536000"]
        )
        .slice(2);
    let privKey = process.env.privateKey;
    let account = xdc.eth.accounts.privateKeyToAccount(privKey);
    console.log(account, account.address);
    let txData = { data: data, from: account.address, gas: 4700000 };
    xdc.eth.getTransactionCount(account.address, "pending").then((nonce) => {
      txData["nonce"] = nonce;
      xdc.eth.accounts
        .signTransaction(txData, account.privateKey)
        .then((signed) => {
          xdc.eth
            .sendSignedTransaction(signed.rawTransaction)
            .once("transactionHash", console.log)
            .on("receipt", (receipt) => {
              console.log(receipt);
              resolve(receipt);
            });
        })
        .catch((e) => {
          console.log("error while deploying contract", e);
        });
    });
  });
}

exports.DeployStakingContract = DeployStakingContract;
