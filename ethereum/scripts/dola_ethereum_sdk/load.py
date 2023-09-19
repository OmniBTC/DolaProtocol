import json
from brownie import Contract

from dola_ethereum_sdk import DOLA_CONFIG, config


def womrhole_package(network):
    package_address = config["networks"][network]["wormhole"]
    return Contract.from_abi("IWormhole", package_address,
                             getattr(DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"].interface, "IWormhole").abi)


def wormhole_adapter_pool_package(network, package_address=None):
    if package_address is None:
        package_address = config["networks"][network]["wormhole_adapter_pool"]["latest"]
    return Contract.from_abi("WormholeAdapterPool", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["WormholeAdapterPool"].abi)

def bool_adapter_pool_package(network, package_address=None):
    if package_address is None:
        package_address = config["networks"][network]["bool_adapter_pool"]["latest"]
    return Contract.from_abi("BoolAdapterPool", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["BoolAdapterPool"].abi)


def dola_pool_package(network, package_address=None):
    if package_address is None:
        package_address = config["networks"][network]["dola_pool"]
    return Contract.from_abi("DolaPool", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["DolaPool"].abi)


def lending_portal_package(network):
    package_address = config["networks"][network]["lending_portal"]
    return Contract.from_abi("LendingPortal", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortal"].abi)


def system_portal_package(network):
    package_address = config["networks"][network]["system_portal"]
    return Contract.from_abi("SystemPortal", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortal"].abi)

def lending_portal_bool_package(network):
    package_address = config["networks"][network]["lending_portal_bool"]
    return Contract.from_abi("LendingPortal", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["LendingPortalBool"].abi)


def system_portal_bool_package(network):
    package_address = config["networks"][network]["system_portal_bool"]
    return Contract.from_abi("SystemPortal", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["SystemPortalBool"].abi)


def test_coins_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1]


def erc20_package(package_address):
    return Contract.from_abi("ERC20", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)


def w3_erc20_package(w3_eth, package_address):
    return w3_eth.contract(package_address, abi=DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)


def bool_messenger_package(package_address):
    messenger_abi_json = """[
	{
		"inputs": [
			{
				"components": [
					{
						"internalType": "bytes32",
						"name": "txUniqueIdentification",
						"type": "bytes32"
					},
					{
						"internalType": "bytes32",
						"name": "crossType",
						"type": "bytes32"
					},
					{
						"internalType": "bytes32",
						"name": "srcAnchor",
						"type": "bytes32"
					},
					{
						"internalType": "bytes",
						"name": "bnExtraFeed",
						"type": "bytes"
					},
					{
						"internalType": "bytes32",
						"name": "dstAnchor",
						"type": "bytes32"
					},
					{
						"internalType": "bytes",
						"name": "payload",
						"type": "bytes"
					}
				],
				"internalType": "struct IMsgReceiver.Message",
				"name": "message",
				"type": "tuple"
			},
			{
				"internalType": "bytes",
				"name": "signature",
				"type": "bytes"
			}
		],
		"name": "receiveFromBool",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	}
]"""

    messenger_abi = json.loads(messenger_abi_json)

    return Contract.from_abi("Messenger", package_address, messenger_abi)

def bool_anchor_package(anchor_address):
    anchor_abi_json = """
[
	{
		"inputs": [
			{
				"internalType": "string",
				"name": "name_",
				"type": "string"
			},
			{
				"internalType": "address",
				"name": "deployer_",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "committee_",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "messenger_",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "factory_",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "anchorLibrary_",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "relayer_",
				"type": "address"
			}
		],
		"stateMutability": "nonpayable",
		"type": "constructor"
	},
	{
		"inputs": [
			{
				"internalType": "uint256",
				"name": "actualFee",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "requiredFee",
				"type": "uint256"
			}
		],
		"name": "INSUFFICIENT_RELAYER_FEE",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "uint32",
				"name": "pathId",
				"type": "uint32"
			}
		],
		"name": "INVALID_PATH",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "wrongConsumer",
				"type": "address"
			}
		],
		"name": "NOT_CONSUMER",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "sender",
				"type": "address"
			}
		],
		"name": "NOT_MANAGER",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "NULL_ADDRESS",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "NULL_ANCHOR",
		"type": "error"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "address",
				"name": "previousConsumer",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "newConsumer",
				"type": "address"
			}
		],
		"name": "ConsumerUpdated",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "previousManager",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "newManager",
				"type": "address"
			}
		],
		"name": "ManagerUpdated",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "bytes32",
				"name": "txUniqueIdentification",
				"type": "bytes32"
			},
			{
				"indexed": false,
				"internalType": "bytes",
				"name": "reason",
				"type": "bytes"
			}
		],
		"name": "MessageDeliverFailed",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": false,
				"internalType": "address",
				"name": "previousRelayer",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "address",
				"name": "newRelayer",
				"type": "address"
			}
		],
		"name": "RelayerUpdated",
		"type": "event"
	},
	{
		"inputs": [],
		"name": "anchorLibrary",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "uint32[]",
				"name": "remoteChainIds",
				"type": "uint32[]"
			},
			{
				"internalType": "bytes32[]",
				"name": "remoteAnchors",
				"type": "bytes32[]"
			}
		],
		"name": "batchUpdateRemoteAnchors",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "committee",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "consumer",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "factory",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "uint32",
				"name": "remoteChainId",
				"type": "uint32"
			}
		],
		"name": "fetchRemoteAnchor",
		"outputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "uint32",
				"name": "remoteChainId",
				"type": "uint32"
			}
		],
		"name": "isPathEnabled",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "manager",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "messenger",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "name",
		"outputs": [
			{
				"internalType": "string",
				"name": "",
				"type": "string"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "txUniqueIdentification",
				"type": "bytes32"
			},
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			},
			{
				"internalType": "bytes",
				"name": "",
				"type": "bytes"
			},
			{
				"internalType": "bytes",
				"name": "payload",
				"type": "bytes"
			}
		],
		"name": "receiveFromMessenger",
		"outputs": [
			{
				"internalType": "enum IAnchor.MessageStatus",
				"name": "status",
				"type": "uint8"
			}
		],
		"stateMutability": "payable",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "relayer",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address payable",
				"name": "refundAddress",
				"type": "address"
			},
			{
				"internalType": "bytes32",
				"name": "crossType",
				"type": "bytes32"
			},
			{
				"internalType": "bytes",
				"name": "extraFeed",
				"type": "bytes"
			},
			{
				"internalType": "uint32",
				"name": "dstChainId",
				"type": "uint32"
			},
			{
				"internalType": "bytes",
				"name": "payload",
				"type": "bytes"
			}
		],
		"name": "sendToMessenger",
		"outputs": [
			{
				"internalType": "bytes32",
				"name": "txUniqueIdentification",
				"type": "bytes32"
			}
		],
		"stateMutability": "payable",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "totalRemotePaths",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newConsumer",
				"type": "address"
			}
		],
		"name": "updateConsumer",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newManager",
				"type": "address"
			}
		],
		"name": "updateManager",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "newRelayer",
				"type": "address"
			}
		],
		"name": "updateRelayer",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	}
]
"""

    anchor_abi = json.loads(anchor_abi_json)

    return Contract.from_abi("Anchor", anchor_address, anchor_abi)