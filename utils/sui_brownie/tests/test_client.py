import unittest

from sui_client import SuiClient


class TestSuiBrownie(unittest.TestCase):
    @staticmethod
    def get_base_url(net):
        if net == "devnet":
            return "https://fullnode.devnet.sui.io:443"
        elif net == "testnet":
            return "https://fullnode.testnet.sui.io:443"
        else:
            return

    def test_sui_getNormalizedMoveModulesByPackage(self):
        base_url = self.get_base_url("devnet")
        client = SuiClient(base_url, timeout=30)
        result = client.sui_getNormalizedMoveModulesByPackage(
            "0xf9c4950f21684d08c742c5bc6ca051cc16a05764a08450a9c83eac782eca8cc9")
        print(result)
