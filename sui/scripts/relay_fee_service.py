from pathlib import Path

from flask import Flask
from flask_cors import CORS

import dola_ethereum_sdk
import relayer

app = Flask(__name__)
CORS(app)


@app.route('/unrelay_txs/<src_chain_id>/<call_name>')
@app.route('/unrelay_txs/<src_chain_id>/<call_name>/<limit>')
def unrelay_txs(src_chain_id, call_name, limit=0):
    return relayer.get_unrelay_txs(src_chain_id, call_name, limit)


@app.route('/unrelay_tx/<src_chain_id>/<sequence>')
def unrelay_tx(src_chain_id, sequence):
    return relayer.get_unrelay_tx_by_sequence(src_chain_id, sequence)


@app.route('/relay_fee/<src_chain_id>/<dst_chain_id>/<call_name>')
@app.route('/relay_fee/<src_chain_id>/<dst_chain_id>/<call_name>/<feed_nums>')
def relay_fee(src_chain_id, dst_chain_id, call_name, feed_nums=0):
    return relayer.get_relay_fee(src_chain_id, dst_chain_id, call_name, feed_nums)


@app.route('/max_relay_fee/<src_chain_id>/<dst_chain_id>/<call_name>')
def max_relay_fee(src_chain_id, dst_chain_id, call_name):
    return relayer.get_max_relay_fee(src_chain_id, dst_chain_id, call_name)


if __name__ == '__main__':
    dola_ethereum_sdk.set_dola_project_path(Path("../.."))

    app.run(host='::', port=5000)
