from pathlib import Path
from typing import Union

import sui_brownie

DOLA_CONFIG = {
    "DOLA_PROJECT_PATH": Path(__file__).parent.parent.parent.parent,
    "DOLA_SUI_PATH": Path(__file__).parent.parent.parent.parent.joinpath("sui")
}

SUI_ENDPOINTS = [
    "https://sui-mainnet.coming.chat:443",
    "https://sui-rpc-mainnet.testnet-pride.com:443",
    "https://sui-mainnet.nodeinfra.com:443",
    "https://mainnet-rpc.sui.chainbase.online:443",
    "https://sui-mainnet-ca-1.cosmostation.io:443",
    "https://sui-mainnet-ca-2.cosmostation.io:443",
    "https://sui-mainnet-eu-1.cosmostation.io:443",
    "https://mainnet.suiet.app:443",
    "https://sui-mainnet-eu-2.cosmostation.io:443",
    "https://explorer-rpc.mainnet.sui.io:443",
    "https://sui-mainnet-eu-3.cosmostation.io:443",
    "https://sui-mainnet-eu-4.cosmostation.io:443",
    "https://sui-mainnet-us-1.cosmostation.io:443",
    "https://sui-mainnet-us-2.cosmostation.io:443",
    "https://mainnet.sui.rpcpool.com:443",
    "https://sui-mainnet-endpoint.blockvision.org:443",
    "https://rpc-mainnet.suiscan.xyz:443",
    "https://sui-mainnet.blockeden.xyz:443",
    "https://sui-mainnet-rpc.allthatnode.com:443",
    "https://sui-mainnet-rpc-germany.allthatnode.com:443",
    "https://sui-mainnet-rpc-korea.allthatnode.com:443",
    "https://sui-mainnet-rpc.bartestnet.com:443",
    "https://sui1mainnet-rpc.chainode.tech:443",
    "https://sui-rpc-mainnet.brightlystake.com:443"
]

sui_project = sui_brownie.SuiProject(project_path=DOLA_CONFIG["DOLA_SUI_PATH"], network="sui-mainnet")
sui_project.add_endpoints(SUI_ENDPOINTS)


def set_dola_project_path(path: Union[Path, str], network="sui-mainnet"):
    global sui_project
    if isinstance(path, str):
        path = Path(path)
    DOLA_CONFIG["DOLA_PROJECT_PATH"] = path
    DOLA_CONFIG["DOLA_SUI_PATH"] = path.joinpath("sui")
    assert DOLA_CONFIG["DOLA_SUI_PATH"].exists(), f"Path error:{DOLA_CONFIG['DOLA_SUI_PATH'].absolute()}!"
    sui_project = sui_brownie.SuiProject(project_path=DOLA_CONFIG["DOLA_SUI_PATH"], network=network)
    sui_project.load_config()
    sui_project.read_cache()
