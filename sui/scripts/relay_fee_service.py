from flask import Flask

import relayer

app = Flask(__name__)


@app.route('/relay_fee/<src_chain_id>/<dst_chain_id>/<call_name>')
def relay_fee(src_chain_id, dst_chain_id, call_name):
    return relayer.calculate_relay_fee(src_chain_id, dst_chain_id, call_name)


if __name__ == '__main__':
    app.run()
