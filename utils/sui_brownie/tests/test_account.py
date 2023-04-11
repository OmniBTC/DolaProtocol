import unittest

from sui_brownie import Account


class TestAccount(unittest.TestCase):
    TEST_CASES = [
        [
            'film crazy soon outside stand loop subway crumble thrive popular green nuclear struggle pistol arm wife phrase warfare march wheat nephew ask sunny firm',
            'AN0JMHpDum3BhrVwnkylH0/HGRHBQ/fO/8+MYOawO8j6',
            '0xa2d14fad60c56049ecf75246a481934691214ce413e6a8ae2fe6834c173a6133',
        ],
        [
            'require decline left thought grid priority false tiny gasp angle royal system attack beef setup reward aunt skill wasp tray vital bounce inflict level',
            'AJrA997C1eVz6wYIp7bO8dpITSRBXpvg1m70/P3gusu2',
            '0x1ada6e6f3f3e4055096f606c746690f1108fcc2ca479055cc434a3e1d3f758aa',
        ],
        [
            'organ crash swim stick traffic remember army arctic mesh slice swear summer police vast chaos cradle squirrel hood useless evidence pet hub soap lake',
            'AAEMSIQeqyz09StSwuOW4MElQcZ+4jHW4/QcWlJEf5Yk',
            '0xe69e896ca10f5a77732769803cc2b5707f0ab9d4407afb5e4b4464b89769af14',
        ],
    ]

    def test_account(self):
        # verify account
        for mnemonic, pubkey, address in self.TEST_CASES:
            acc = Account(mnemonic=mnemonic)
            assert acc.account_address == address, f"{acc.account_address}--{address}"

        # verify sign
        msg = b"hello world"
        for mnemonic, pubkey, address in self.TEST_CASES:
            acc = Account(mnemonic=mnemonic)
            assert acc.public_key().verify(msg, acc.private_key.sign(msg))
