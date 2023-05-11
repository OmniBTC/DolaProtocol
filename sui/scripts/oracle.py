import base64
import time
from pathlib import Path

import ccxt
import requests
import sui_brownie

from dola_sui_sdk import load, sui_project, init


def parse_u64(data: list):
    output = 0
    for i in range(8):
        output = (output << 8) + int(data[7 - i])
    return output


def pyth_state():
    return sui_project.network_config['objects']['PythState']


def load_pyth():
    return sui_brownie.SuiPackage(
        package_id=sui_project.network_config['packages']['pyth'],
        package_path=Path.home().joinpath(Path(
            ".move/https___github_com_OmniBTC_pyth-crosschain_git_8601609d6f4f64fb9a42ec7704aae3cf3a47e140"
            "/target_chains/sui/contracts")),
    )


def deploy_oracle():
    oracle_package = sui_brownie.SuiPackage(
        package_path=Path("../").joinpath("oracle")
    )

    oracle_package.program_publish_package(replace_address=dict(
        wormhole=sui_project.network_config['packages']['wormhole'],
        pyth=sui_project.network_config['packages']['pyth'],
    ))


def get_feed_vaa(symbol):
    pyth_service_url = sui_project.network_config['pyth_service_url']
    feed_id = sui_project.network_config['oracle'][symbol].replace("0x", "")
    url = f"{pyth_service_url}/api/latest_vaas?ids[]={feed_id}"
    response = requests.get(url)
    vaa = list(response.json())[0]
    return f"0x{base64.b64decode(vaa).hex()}"


def get_price_info_object(symbol):
    result = sui_project.client.suix_getDynamicFields(
        pyth_state(),
        None,
        None
    )
    name = list(b"price_info")
    price_inentifier_table = [field['objectId'] for field in result['data'] if field['name']['value'] == name][0]

    result = sui_project.client.suix_getDynamicFields(price_inentifier_table, None, None)
    feed_id = sui_project.network_config['oracle'][symbol].replace("0x", "")
    if price_info_object_field := [
        field['objectId']
        for field in result['data']
        if field['name']['value']['bytes'] == list(bytes.fromhex(feed_id))
    ]:
        result = sui_project.client.sui_getObject(price_info_object_field[0], {'showContent': True})
        return result['data']['content']['fields']['value']
    else:
        raise BaseException("Price info object not found")


def get_pyth_fee():
    pyth = load_pyth()

    result = pyth.state.get_base_update_fee.inspect(pyth_state())
    return parse_u64(result['results'][0]['returnValues'][0][0])


def feed_token_price_for_pyth(symbol):
    oracle = load.oracle_package()

    pyth_fee_amount = get_pyth_fee()
    wormhole_state = sui_project.network_config['objects']['WormholeState']

    result = sui_project.pay_sui([pyth_fee_amount])
    fee_coin = result['objectChanges'][-1]['objectId']

    oracle.oracle.feed_token_price_for_pyth(
        wormhole_state,
        pyth_state(),
        [get_price_info_object(symbol)],
        list(bytes.fromhex(get_feed_vaa(symbol).replace("0x", ""))),
        init.clock(),
        fee_coin
    )


def get_pool_id(symbol):
    if symbol == "BTC/USDT":
        return 0
    elif symbol == "ETH/USDT":
        return 3
    elif symbol == "MATIC/USDT":
        return 4
    elif symbol == "APT/USDT":
        return 5
    elif symbol == "BNB/USDT":
        return 6


def get_market_prices(symbols=("BTC/USDT", "ETH/USDT")):
    api = ccxt.kucoin()
    api.load_markets()
    prices = {}

    for symbol in symbols:
        result = api.fetch_ticker(symbol=symbol)
        price = result["close"]
        print(f"Symbol:{symbol}, price:{price}")
        prices[symbol] = price
    return prices


def check_sui_objects():
    sui_objects = sui_project.get_account_sui()
    if len(sui_objects) > 1:
        sui_project.pay_all_sui()


def feed_market_price(symbols=("BTC/USDT", "ETH/USDT")):
    kucoin = ccxt.kucoin()
    kucoin.load_markets()

    sui_project.active_account("Oracle")
    oracle = load.oracle_package()
    while True:
        check_sui_objects()
        for symbol in symbols:
            try:
                price = kucoin.fetch_ticker(symbol)['close']
                oracle.oracle.update_token_price(
                    oracle.oracle.OracleCap[-1],
                    oracle.oracle.PriceOracle[-1],
                    get_pool_id(symbol),
                    int(price * 100)
                )
            except Exception as e:
                print(e)
                continue
        time.sleep(600)


if __name__ == '__main__':
    # deploy_oracle()
    feed_token_price_for_pyth('BTC/USD')
