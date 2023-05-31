from pathlib import Path

import dola_ethereum_sdk
import relayer
from flask import Flask

app = Flask(__name__)


@app.route('/relay_fee/<src_chain_id>/<dst_chain_id>/<call_name>')
def relay_fee(src_chain_id, dst_chain_id, call_name):
    return relayer.get_relay_fee(src_chain_id, dst_chain_id, call_name)


@app.route('/max_relay_fee/<src_chain_id>/<dst_chain_id>/<call_name>')
def max_relay_fee(src_chain_id, dst_chain_id, call_name):
    return relayer.get_max_relay_fee(src_chain_id, dst_chain_id, call_name)


if __name__ == '__main__':
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    app.run()
