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


def test_coins_package():
    return DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MockToken"][-1]


def erc20_package(package_address):
    return Contract.from_abi("ERC20", package_address,
                             DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)


def w3_erc20_package(w3_eth, package_address):
    return w3_eth.contract(package_address, abi=DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["ERC20"].abi)


def booltest_consumer_package(package_address):
    return Contract.from_abi(
        "MessageBridge",
        package_address,
        DOLA_CONFIG["DOLA_ETHEREUM_PROJECT"]["MessageBridge"].abi
    )


def booltest_messenger_package(package_address):
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
